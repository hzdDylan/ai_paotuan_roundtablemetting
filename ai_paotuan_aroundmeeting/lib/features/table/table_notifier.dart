import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../engine/archive/archiver.dart';
import '../../engine/dice/dice.dart';
import '../../engine/director/director.dart';
import '../../engine/knowledge/audience.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/moderation/moderation.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/bp_names.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/scenario/scene_flow.dart';
import '../../engine/store/event_store.dart';
import '../../engine/turn/action_suggestion.dart';
import '../../engine/turn/actor_turn.dart';
import '../../engine/turn/kp_turn.dart';
import '../../llm/llm_client.dart';
import '../../llm/prompts.dart';
import '../../llm/schema.dart';
import '../../platform/ports.dart';

enum TableStatus { idle, loading, playing, awaitingInput, ended, error }

const Object _keep = Object();

class TableState {
  const TableState({
    this.status = TableStatus.idle,
    this.sessionId = '',
    this.scenarioId = '',
    this.sceneName = '门廊',
    this.speaker = '',
    this.segment = '',
    this.dice,
    this.events = const <GameEvent>[],
    this.busy = false,
    this.errorCode,
    this.errorMessage,
    this.interjectReason = '还没开场',
    this.partySize = 4,
    this.inputRejected,
    this.ended = false,
    this.suggestions = const <ActionSuggestion>[],
    this.bpNames = const <String>[],
  });

  final TableStatus status;
  final String sessionId;

  /// 本局所用剧本 id；切换剧本时用来判断是否还能续上旧局。
  final String scenarioId;
  final String sceneName;
  final String speaker;
  final String segment;
  final Roll? dice;
  final List<GameEvent> events;
  final bool busy;
  final String? errorCode;
  final String? errorMessage;
  final String? interjectReason;
  final int partySize;
  final String? inputRejected;
  final bool ended;

  /// 本局实际使用的 BP 名字（已按对局设置改名）。
  final List<String> bpNames;

  /// 由 LLM 根据当前场景生成的建议行动。
  final List<ActionSuggestion> suggestions;

  bool get canInterject => interjectReason == null && busy;
  bool get awaitingInput => status == TableStatus.awaitingInput;

  TableState copyWith({
    TableStatus? status,
    String? sessionId,
    String? scenarioId,
    String? sceneName,
    String? speaker,
    String? segment,
    Object? dice = _keep,
    List<GameEvent>? events,
    bool? busy,
    Object? errorCode = _keep,
    Object? errorMessage = _keep,
    Object? interjectReason = _keep,
    int? partySize,
    Object? inputRejected = _keep,
    bool? ended,
    List<ActionSuggestion>? suggestions,
    List<String>? bpNames,
  }) => TableState(
    status: status ?? this.status,
    sessionId: sessionId ?? this.sessionId,
    scenarioId: scenarioId ?? this.scenarioId,
    sceneName: sceneName ?? this.sceneName,
    speaker: speaker ?? this.speaker,
    segment: segment ?? this.segment,
    dice: identical(dice, _keep) ? this.dice : dice as Roll?,
    events: events ?? this.events,
    busy: busy ?? this.busy,
    errorCode: identical(errorCode, _keep)
        ? this.errorCode
        : errorCode as String?,
    errorMessage: identical(errorMessage, _keep)
        ? this.errorMessage
        : errorMessage as String?,
    interjectReason: identical(interjectReason, _keep)
        ? this.interjectReason
        : interjectReason as String?,
    partySize: partySize ?? this.partySize,
    inputRejected: identical(inputRejected, _keep)
        ? this.inputRejected
        : inputRejected as String?,
    ended: ended ?? this.ended,
    suggestions: suggestions ?? this.suggestions,
    bpNames: bpNames ?? this.bpNames,
  );
}

final tableProvider = NotifierProvider<TableNotifier, TableState>(
  TableNotifier.new,
);

/// 一局的编排（SE §6.2）：选人 → 组上下文 → LLM → 检定 → 掷骰 → 叙述 → 落盘。
class TableNotifier extends Notifier<TableState> {
  final PromptBuilder _prompts = const PromptBuilder();
  final RngPort _rng = SecureRng();
  final List<GameEvent> _events = <GameEvent>[];
  final List<Roll> _rolls = <Roll>[];

  Scenario? _scenario;
  SceneDef? _scene;
  CharacterSheet? _character;
  LlmClient? _client;
  EventStore? _store;
  Archiver? _archiver;
  Director? _director;
  List<ActorRef> _participants = const <ActorRef>[];
  LocalModerator? _moderator;

  String _kpModel = 'deepseek-chat';
  String _bpModel = 'deepseek-chat';
  String _sceneId = '';
  String? _lastSpeakerId;
  final Map<String, int> _beatsSince = <String, int>{};
  final Set<String> _revealedClues = <String>{};
  final Set<String> _flags = <String>{};
  final Map<String, int> _clockValues = <String, int>{};
  bool _forceBpAfterFail = false;

  /// P1：每个人「憋着没说」的程度 0–10。
  final Map<String, int> _initiative = <String, int>{};
  String _lastUtterance = '';
  bool _lastDramatic = false;
  int _lastSideChatSeq = -99;

  /// 上一条气泡出现的时间：AI 换人说话时至少停留 2 秒，避免被秒顶。
  DateTime? _lastSegmentAt;
  static const Duration _minSegmentDwell = Duration(milliseconds: 3500);
  int _seq = 0;
  int _rollSeq = 0;
  DateTime _startedAt = DateTime.now();
  CancelToken? _bpCancel;

  @override
  TableState build() => const TableState();

  // -------------------------------------------------------------------------
  // 开局
  // -------------------------------------------------------------------------

  Future<void> start() async {
    state = state.copyWith(
      status: TableStatus.loading,
      busy: true,
      segment: '',
      errorCode: null,
      errorMessage: null,
      inputRejected: null,
      ended: false,
    );

    try {
      final loaded = await ref.read(scenarioProvider.future);
      final character = ref.read(characterProvider);
      final settings = ref.read(settingsProvider);
      final key = await ref.read(secretStoreProvider).read(SecretKeys.apiKey);

      if (key == null || key.trim().isEmpty) {
        _fail('E_NO_KEY', '先在设置里填 API key');
        return;
      }

      final dir = await ref.read(fileDirsProvider).appData();

      // 每局随机 BP 名字（不重复），整局保持一致。
      final scenario = _withConfiguredBp(
        loaded,
        ref.read(sessionConfigProvider),
      );
      final scene = scenario.scenes.first;

      _scenario = scenario;
      _scene = scene;
      _sceneId = scene.id;
      _clockValues
        ..clear()
        ..addEntries(
          scene.clocks.map((clock) => MapEntry(clock.id, clock.max)),
        );
      _flags.clear();
      _character = character;
      _kpModel = settings.kpModel;
      _bpModel = settings.bpModel;
      _client = LlmClient(baseUrl: settings.baseUrl, apiKey: key.trim());
      _store = FileEventStore(dir);
      _archiver = Archiver(dir);
      _director = Director();
      _moderator = LocalModerator(scope: scenario.contentScope);
      _participants = _buildParticipants(scenario);
      _startedAt = DateTime.now();

      _events.clear();
      _revealedClues.clear();
      _forceBpAfterFail = false;
      _initiative.clear();
      _lastUtterance = '';
      _lastDramatic = false;
      _lastSideChatSeq = -99;
      _lastSegmentAt = null;
      _rolls.clear();
      _beatsSince.clear();
      _lastSpeakerId = null;
      _seq = 0;
      _rollSeq = 0;

      state = state.copyWith(
        status: TableStatus.playing,
        sessionId: 'sess_${_startedAt.millisecondsSinceEpoch}',
        scenarioId: scenario.id,
        sceneName: scene.name,
        partySize: scenario.partySize,
        bpNames: scenario.bpActors.map((actor) => actor.name).toList(),
        busy: true,
        speaker: 'KP',
        events: const <GameEvent>[],
        suggestions: const <ActionSuggestion>[],
      );

      await _append(<GameEvent>[
        _event(
          EventKind.sessionStart,
          const Audience.public(),
          payload: <String, dynamic>{'scenario': scenario.id},
        ),
        _event(
          EventKind.sceneStart,
          const Audience.public(),
          payload: <String, dynamic>{'scene': scene.id, 'goal': scene.goal},
        ),
      ]);

      await _runOpening();
      // 开场拍只属于 KP：描述完背景后直接轮到玩家，BP 不得抢在玩家之前行动。
      if (!state.ended) await _awaitHuman();
    } on LlmException catch (error) {
      if (error.code == 'E_CANCELLED') {
        state = state.copyWith(busy: false);
        return;
      }
      _fail(error.code, error.message);
    } on SchemaException catch (error) {
      _fail('E_PARSE', error.message);
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
    }
  }

  // -------------------------------------------------------------------------
  // 推进
  // -------------------------------------------------------------------------

  Future<void> advance() async {
    if (state.busy || state.ended) return;
    state = state.copyWith(
      busy: true,
      interjectReason: 'AI 正在说话，可以插话',
      inputRejected: null,
    );
    try {
      await _advanceUntilHuman(maxSteps: 2);
    } on LlmException catch (error) {
      if (error.code == 'E_CANCELLED') {
        state = state.copyWith(busy: false);
        return;
      }
      _fail(error.code, error.message);
    } on SchemaException catch (error) {
      _fail('E_PARSE', error.message);
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
    }
  }

  Future<void> submitPlayer(String raw, {String? checkHint}) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy || state.ended) return;

    final moderator = _moderator;
    if (moderator == null) return;

    // 提交后立即收起选项与输入，直到下一个「我的回合」。
    state = state.copyWith(
      status: TableStatus.playing,
      busy: true,
      inputRejected: null,
    );
    try {
      var result = moderator.check(text);
      if (result.needsLlm) {
        result = await _moderateWithLlm(text);
      }
      if (!result.passes) {
        state = state.copyWith(
          busy: false,
          status: TableStatus.awaitingInput,
          inputRejected: _rejectionCopy(result),
        );
        return;
      }

      final human = _participants.firstWhere(
        (actor) => actor.kind == ActorKind.human,
        orElse: () =>
            const ActorRef(id: 'human', name: '你', kind: ActorKind.human),
      );

      await _append(<GameEvent>[
        _event(
          EventKind.dialogue,
          const Audience.public(),
          actorId: human.id,
          payload: <String, dynamic>{
            'text': text,
            'intent': 'act',
            'speaker': human.name,
          },
        ),
        _event(
          EventKind.inputAllowed,
          const Audience.kpOnly(),
          payload: <String, dynamic>{'stage': result.stage.name},
        ),
      ]);

      _markSpoken(human.id);
      await _emitSegment('你', text);

      final hint = checkHint?.trim() ?? '';
      await _runKpRespond(
        human,
        instruction:
            '玩家刚说了/做了上面最后一条，请回应。'
            '${hint.isEmpty ? '' : '这个动作偏向【$hint】；如果需要检定，优先用它。'}',
      );
      await _advanceUntilHuman(maxSteps: 2);
    } on LlmException catch (error) {
      if (error.code == 'E_CANCELLED') {
        state = state.copyWith(busy: false);
        return;
      }
      _fail(error.code, error.message);
    } on SchemaException catch (error) {
      _fail('E_PARSE', error.message);
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
    }
  }

  /// 插话：只在 BP/NPC 说话时可用（D-08）。
  Future<void> interject() async {
    if (!state.canInterject) return;
    final target = state.speaker;
    _bpCancel?.cancel('interjected');
    _bpCancel = null;

    await _append(<GameEvent>[
      _event(
        EventKind.interjection,
        const Audience.public(),
        actorId: 'human',
        payload: <String, dynamic>{'target': target, 'phase': 'generating'},
      ),
    ]);

    final cut = state.segment.isEmpty ? '' : '${state.segment}……';
    state = state.copyWith(
      status: TableStatus.awaitingInput,
      busy: false,
      speaker: '你',
      segment: cut,
      interjectReason: '轮到你了',
    );
  }

  /// 自动归档（D-24 / V-21：玩家不触发、不感知）。
  Future<ArchiveRecord?> endAndArchive({
    String endingId = 'auto',
    String endingTitle = '本局结束',
  }) async {
    if (state.sessionId.isEmpty || state.ended) return null;
    final scenario = _scenario;
    final character = _character;
    final archiver = _archiver;
    if (scenario == null || character == null || archiver == null) return null;

    final oneLine = _endingLine();
    final review = await _buildReview(endingTitle);
    if (review.isNotEmpty) await _emitSegment('KP', review);

    await _append(<GameEvent>[
      _event(
        EventKind.sessionEnd,
        const Audience.public(),
        payload: <String, dynamic>{'ending': endingId, 'review': review},
      ),
    ]);

    final record = await archiver.seal(
      sessionId: state.sessionId,
      scenario: scenario,
      character: character,
      events: _events,
      rolls: _rolls,
      startedAt: _startedAt,
      endingId: endingId,
      endingTitle: endingTitle,
      oneLine: oneLine,
      review: review,
    );

    state = state.copyWith(
      status: TableStatus.ended,
      ended: true,
      busy: false,
      interjectReason: '本局已结束',
      segment: review.isEmpty ? null : review,
      speaker: review.isEmpty ? null : 'KP',
    );
    return record;
  }

  /// 结局后让 KP 复盘；失败时用不依赖网络的收束文案，绝不阻断归档。
  Future<String> _buildReview(String endingTitle) async {
    final scenario = _scenario;
    final character = _character;
    final client = _client;
    if (scenario == null || character == null || client == null) {
      return _fallbackReview(endingTitle);
    }
    try {
      final cancel = CancelToken();
      final timer = Timer(
        const Duration(seconds: 8),
        () => cancel.cancel('review timeout'),
      );
      try {
        final result = await client.chatJson(
          model: _kpModel,
          messages: _prompts.kpReview(
            scenario: scenario,
            endingTitle: endingTitle,
            characterName: character.name.isEmpty ? '你' : character.name,
            events: _events,
            rolls: _rolls,
          ),
          temperature: 0.7,
          maxTokens: 220,
          cancelToken: cancel,
        );
        final text = result.json['review']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text.length <= 180 ? text : '${text.substring(0, 180)}…';
        }
      } finally {
        timer.cancel();
      }
    } catch (_) {
      // 复盘失败不能影响归档。
    }
    return _fallbackReview(endingTitle);
  }

  String _fallbackReview(String endingTitle) {
    final sceneName = _scene?.name ?? '桌上';
    return '这一局收在「$endingTitle」。你们在$sceneName留下了 '
        '${_rolls.length} 次检定；有些话没有说完，但门已经关上。';
  }

  // -------------------------------------------------------------------------
  // 内部流程
  // -------------------------------------------------------------------------

  Future<void> _runOpening() async {
    final scenario = _scenario!;
    final scene = _scene!;

    // 固定开场白直接播，不花 token 让模型重写（也保证每局开头一致）。
    final fixedOpening = scenario.opening.trim();
    if (fixedOpening.isNotEmpty) {
      await _emitSegment('KP', fixedOpening);
      await _append(<GameEvent>[
        _event(
          EventKind.narration,
          const Audience.public(),
          payload: <String, dynamic>{'text': fixedOpening, 'speaker': 'KP'},
        ),
      ]);
      return;
    }
    final messages = _prompts.kpTurn(
      scenario: scenario,
      scene: scene,
      events: _events,
      party: _partyRefs(),
      instruction:
          '请开场：只描述时间、地点、气氛与在场者的静态站位，不让任何人说话或行动；'
          '写 1–2 段有画面感的旁白。',
      flags: _flags,
      revealedClues: _revealedClues,
      clocks: _clockValues,
    );

    final kp = await _askKp(messages);
    await _emitSegment('KP', kp.displayText);
    await _append(<GameEvent>[
      _event(
        EventKind.narration,
        const Audience.public(),
        payload: <String, dynamic>{'text': kp.displayText, 'speaker': 'KP'},
      ),
    ]);
    _applyState(kp.state);
    await _handleSignal(kp.signal, kp.nextSceneId);
  }

  Future<void> _advanceUntilHuman({required int maxSteps}) async {
    final bps = _participants
        .where((actor) => actor.kind == ActorKind.bp)
        .toList();

    // P1：只有「玩家普通失败」强制 BP 救场；其余交给冲动值决定谁开口。
    final needBp = _forceBpAfterFail;
    _forceBpAfterFail = false;

    if (needBp && bps.isNotEmpty && !state.ended) {
      await _runBp(bps.first);
      if (state.ended) return;
    }

    for (var step = 0; step < maxSteps; step++) {
      if (state.ended) return;
      final outcome = await _runOneBeat();
      if (outcome == _BeatOutcome.human || state.ended) break;
    }
    if (!state.ended) await _awaitHuman();
  }

  Future<_BeatOutcome> _runOneBeat() async {
    final director = _director;
    if (director == null) return _BeatOutcome.stop;

    final allowSideChat = _seq - _lastSideChatSeq >= 5;
    final pick = director.pick(
      DirectorContext(
        participants: _participants,
        humanId: 'human',
        lastSpeakerId: _lastSpeakerId,
        beatsSinceHuman: _beatsSince['human'] ?? 99,
        beatsSince: Map<String, int>.from(_beatsSince),
        sceneTags: _sceneTags(),
        initiative: Map<String, int>.from(_initiative),
        lastUtterance: _lastUtterance,
        lastEventDramatic: _lastDramatic,
        allowSideChat: allowSideChat,
      ),
    );
    if (pick == null) return _BeatOutcome.stop;

    // 戏剧性只喂给一拍，避免连续几拍都在「余波」里。
    _lastDramatic = false;

    ActorRef? actor;
    for (final candidate in _participants) {
      if (candidate.id == pick.actorId) actor = candidate;
    }
    if (actor == null) return _BeatOutcome.stop;

    if (actor.kind == ActorKind.human) return _BeatOutcome.human;

    if (actor.kind == ActorKind.bp) {
      ActorRef? sideChatTarget;
      if (pick.sideChatTargetId != null) {
        for (final candidate in _participants) {
          if (candidate.id == pick.sideChatTargetId) sideChatTarget = candidate;
        }
        _lastSideChatSeq = _seq;
      }
      await _runBp(actor, sideChatTarget: sideChatTarget);
    } else {
      await _runKpRespond(actor, instruction: '让 ${actor.name} 行动或开口。');
    }
    return _BeatOutcome.ai;
  }

  Future<void> _runBp(ActorRef actor, {ActorRef? sideChatTarget}) async {
    final scenario = _scenario!;
    final scene = _scene!;
    final def = scenario.actorById(actor.id);
    if (def == null) return;

    state = state.copyWith(
      busy: true,
      interjectReason: '${actor.name} 正在说话，可插话',
    );
    _bpCancel = CancelToken();

    final messages = _prompts.bpTurn(
      scenario: scenario,
      scene: scene,
      actor: def,
      events: _events,
      others: _partyNames().where((name) => name != actor.name).toList(),
      lastSpeaker: _lastSpeakerId,
      sideChatTo: sideChatTarget?.name,
    );

    final result = await _client!.chatJson(
      model: _bpModel,
      messages: messages,
      cancelToken: _bpCancel,
    );

    // 不做修复/重试调用（V-24）：一次请求不合法就停下，避免重复烧 token。
    final turn = parseBpTurn(
      result.json,
      selfName: actor.name,
      knownNames: _partyNames().toSet(),
    );
    return _applyBpTurn(actor, turn);
  }

  Future<void> _applyBpTurn(ActorRef actor, ActorTurn turn) async {
    _bpCancel = null;
    await _emitSegment(actor.name, turn.speech);
    await _append(<GameEvent>[
      _event(
        EventKind.dialogue,
        const Audience.public(),
        actorId: actor.id,
        payload: <String, dynamic>{
          'text': turn.speech,
          'intent': turn.intent.name,
          'speaker': actor.name,
          if (turn.action.isNotEmpty) 'action': turn.action,
        },
      ),
    ]);
    _markSpoken(actor.id);

    if (turn.wantsCheckSkill != null) {
      await _runCheck(actor, turn.wantsCheckSkill!);
    } else {
      await _runKpRespond(actor, instruction: '${actor.name} 刚说了上面最后一条，请回应。');
    }
  }

  Future<void> _runCheck(ActorRef actor, Skill skill) async {
    final scenario = _scenario!;
    final scene = _scene!;

    final msg = _prompts.kpTurn(
      scenario: scenario,
      scene: scene,
      events: _events,
      party: _partyRefs(),
      instruction:
          '${actor.name}（id: ${actor.id}）想用【${skill.label}】做一次检定。'
          'checks[0].actor 必须填这个 id。请只给难度与失败代价，不要叙述结果。',
      flags: _flags,
      revealedClues: _revealedClues,
      clocks: _clockValues,
    );
    final declaration = await _askKp(msg);
    final decl =
        declaration.check ??
        CheckDecl(
          actorId: actor.id,
          skill: skill,
          difficulty: Difficulty.regular,
          stakes: '',
        );

    final actorName = actor.kind == ActorKind.human
        ? (_character!.name.isEmpty ? '你' : _character!.name)
        : actor.name;
    await _rollAndNarrate(decls: <CheckDecl>[decl], actorName: actorName);
  }

  /// 一次动作的基础值：玩家看角色卡，BP 统一 55，NPC 用剧本基础值。
  int _baseValueFor(CheckDecl decl) {
    final isBp = _participants.any(
      (actor) => actor.id == decl.actorId && actor.kind == ActorKind.bp,
    );
    if (decl.actorId == 'human') {
      if (decl.skill != null) return _character!.skills[decl.skill!];
      return _character!.attributes[decl.attribute!];
    }
    if (isBp) return bpSkillValue;
    return decl.skill?.baseValue ?? attributeBase;
  }

  /// 掷骰 → 落库/展示 → KP 统一叙述（一个动作或多动作共用）。
  Future<void> _rollAndNarrate({
    required List<CheckDecl> decls,
    required String actorName,
  }) async {
    final scenario = _scenario!;
    final scene = _scene!;
    final rolls = <Roll>[];
    final events = <GameEvent>[];
    SceneFumble? fatal;

    for (final decl in decls) {
      final baseSkill = _baseValueFor(decl);
      final roll = resolveCheck(
        decl: decl,
        baseSkill: baseSkill,
        seq: ++_rollSeq,
        die: rollDie(_rng),
      );
      if (!roll.outcome.isSuccess) _lastDramatic = true;
      if (decl.actorId == 'human' && roll.outcome == Outcome.fail) {
        _forceBpAfterFail = true;
      }
      _rolls.add(roll);
      rolls.add(roll);

      events.add(
        _event(
          EventKind.checkDeclared,
          const Audience.public(),
          actorId: decl.actorId,
          payload: <String, dynamic>{
            'skill': decl.label,
            'base_skill': baseSkill,
            'difficulty': decl.difficulty.name,
            'target': roll.target,
            'stakes': decl.stakes,
          },
        ),
      );
      events.add(
        _event(
          EventKind.roll,
          const Audience.public(),
          actorId: decl.actorId,
          payload: roll.toJson(),
        ),
      );
      fatal ??= _fatalFumbleFor(roll, decl.actorId);
    }

    state = state.copyWith(dice: rolls.last);
    await _append(events);

    final narration = await _askKpNarration(
      _prompts.kpNarration(
        scenario: scenario,
        scene: scene,
        rolls: rolls,
        actorName: actorName,
        events: _events,
        fatalConsequence: fatal?.text ?? '',
      ),
    );

    await _emitSegment('KP', narration.displayText);
    await _append(<GameEvent>[
      _event(
        EventKind.checkResult,
        const Audience.public(),
        payload: <String, dynamic>{
          'outcome': rolls.map((roll) => roll.outcome.name).join(','),
          'text': narration.displayText,
          'speaker': 'KP',
          'rolls': rolls.map((roll) => roll.toJson()).toList(),
        },
      ),
    ]);
    _applyState(narration.state);
    if (fatal != null) {
      await _applyFatalFumble(fatal);
      return;
    }
    await _handleSignal(narration.signal, narration.nextSceneId);
  }

  Future<void> _runKpRespond(
    ActorRef actor, {
    required String instruction,
  }) async {
    final scenario = _scenario!;
    final scene = _scene!;

    state = state.copyWith(busy: true, interjectReason: 'KP 正在叙述，不可打断');

    final messages = _prompts.kpTurn(
      scenario: scenario,
      scene: scene,
      events: _events,
      party: _partyRefs(),
      instruction: instruction,
      flags: _flags,
      revealedClues: _revealedClues,
      clocks: _clockValues,
    );
    final kp = await _askKp(messages);
    final checks = _allowedChecks(kp.checks);

    // 不需要检定：直接播 KP 的旁白。
    if (checks.isEmpty) {
      await _emitSegment('KP', kp.displayText);
      await _append(<GameEvent>[
        _event(
          EventKind.narration,
          const Audience.public(),
          payload: <String, dynamic>{'text': kp.displayText, 'speaker': 'KP'},
        ),
      ]);
      _applyState(kp.state);
      await _handleSignal(kp.signal, kp.nextSceneId);
      _markSpoken(actor.id);
      return;
    }

    // 需要检定：先掷骰并落库/展示，再让 KP 统一叙述结果（V-27）。
    _applyState(kp.state);
    // 时钟可能在这一拍归零：先走硬出口，不要继续掷骰。
    if (await _handleSignal(SceneSignal.continueRun, null)) return;

    await _rollAndNarrate(decls: checks, actorName: checks.first.actorId);

    _markSpoken(actor.id);
  }

  /// 刚结算完一次检定时，忽略紧跟着的第二次检定请求。
  ///
  /// 否则 KP 的结算叙述会被误当成「又要求掷骰」，出现连续两次投掷、中间没人说话。
  List<CheckDecl> _allowedChecks(List<CheckDecl> checks) {
    if (checks.isEmpty) return const <CheckDecl>[];
    if (_events.isNotEmpty && _events.last.kind == EventKind.checkResult) {
      return const <CheckDecl>[];
    }
    // 一句话最多结算 3 个动作，避免模型刷检定。
    return checks.take(3).toList();
  }

  /// 只对玩家的大失败生效；BP 的大失败不替玩家结束整局。
  SceneFumble? _fatalFumbleFor(Roll roll, String actorId) {
    final scene = _scene;
    if (scene == null) return null;
    return fatalFumbleFor(scene, roll, actorId);
  }

  Future<void> _applyFatalFumble(SceneFumble fumble) async {
    final scenario = _scenario;
    if (scenario == null) return;
    final target = scenario.sceneById(fumble.ending);
    if (target == null) {
      await endAndArchive(endingId: fumble.ending, endingTitle: '本局结束');
      return;
    }
    if (!target.ending) {
      await endAndArchive(endingId: target.id, endingTitle: target.name);
      return;
    }
    await _moveToScene(target.id);
  }

  /// 结局一句话：取最后一拍有文字的叙述，截到 90 字。
  String _endingLine() {
    for (var i = _events.length - 1; i >= 0; i--) {
      final event = _events[i];
      if (event.kind == EventKind.narration ||
          event.kind == EventKind.checkResult) {
        final text = event.text.trim();
        if (text.isEmpty) continue;
        final flat = text.replaceAll('\n', ' ');
        return flat.length <= 90 ? flat : '${flat.substring(0, 90)}…';
      }
    }
    return '这一局没有留下叙述。';
  }

  /// 处理 KP 的场景信号：时钟归零优先，其次 end / 合法转场。
  ///
  /// 返回 true 表示这一拍之后不能再继续推进（已转场或已收束）。
  Future<bool> _handleSignal(SceneSignal signal, String? nextSceneId) async {
    if (state.ended || state.sessionId.isEmpty) return true;

    // 时钟归零是硬出口，压过 KP 的 continue。
    final zeroTarget = _clockZeroTarget();
    if (zeroTarget != null) {
      await _moveToScene(zeroTarget);
      return true;
    }

    if (signal == SceneSignal.endScene) {
      await endAndArchive();
      return true;
    }

    if (signal == SceneSignal.transition) {
      final target = _validatedExit(nextSceneId) ?? _firstOpenExit();
      if (target != null) {
        await _moveToScene(target);
        return true;
      }
    }
    return false;
  }

  String? _clockZeroTarget() {
    final scene = _scene;
    if (scene == null) return null;
    for (final clock in scene.clocks) {
      if ((_clockValues[clock.id] ?? clock.max) <= 0 &&
          clock.onZero.isNotEmpty) {
        return clock.onZero;
      }
    }
    return null;
  }

  /// 只接受「当前场景确实有、且条件已满足」的出口；防止 KP 硬跳。
  String? _validatedExit(String? requested) {
    final scene = _scene;
    if (scene == null || requested == null || requested.isEmpty) return null;
    if (requested == scene.id) return null;
    for (final exit in scene.exits) {
      if (exit.to != requested) continue;
      if (_isOpen(exit)) return exit.to;
    }
    return null;
  }

  String? _firstOpenExit() {
    final scene = _scene;
    if (scene == null) return null;
    for (final exit in scene.exits) {
      if (_isOpen(exit)) return exit.to;
    }
    return null;
  }

  bool _isOpen(SceneExit exit) => isExitOpen(
    exit,
    flags: _flags,
    clues: _revealedClues,
    clocks: _clockValues,
  );

  Future<void> _moveToScene(String sceneId) async {
    final scenario = _scenario;
    if (scenario == null || state.ended) return;
    if (sceneId == _sceneId) return;

    final next = scenario.sceneById(sceneId);
    if (next == null) return;

    final previous = _scene;
    if (previous != null) {
      await _append(<GameEvent>[
        _event(
          EventKind.sceneEnd,
          const Audience.public(),
          payload: <String, dynamic>{'scene': previous.id},
        ),
      ]);
    }

    _scene = next;
    _sceneId = next.id;
    _clockValues
      ..clear()
      ..addEntries(next.clocks.map((clock) => MapEntry(clock.id, clock.max)));
    _beatsSince.clear();
    _lastSpeakerId = null;

    state = state.copyWith(
      sceneName: next.name,
      suggestions: const <ActionSuggestion>[],
    );

    await _append(<GameEvent>[
      _event(
        EventKind.sceneStart,
        const Audience.public(),
        payload: <String, dynamic>{
          'scene': next.id,
          'goal': next.goal,
          'name': next.name,
        },
      ),
    ]);

    if (next.ending) {
      await endAndArchive(endingId: next.id, endingTitle: next.name);
    }
  }

  Future<KpTurn> _askKp(List<Map<String, String>> messages) async {
    final result = await _client!.chatJson(model: _kpModel, messages: messages);
    return parseKpTurn(
      result.json,
      npcNames: _scenario!.npcs.map((npc) => npc.name).toSet(),
      actorIds: _participants.map((actor) => actor.id).toSet(),
      sceneIds: _scenario!.scenes.map((scene) => scene.id).toSet(),
      humanId: 'human',
    );
  }

  Future<KpNarration> _askKpNarration(
    List<Map<String, String>> messages,
  ) async {
    final result = await _client!.chatJson(model: _kpModel, messages: messages);
    return parseKpNarration(
      result.json,
      npcNames: _scenario!.npcs.map((npc) => npc.name).toSet(),
      sceneIds: _scenario!.scenes.map((scene) => scene.id).toSet(),
    );
  }

  Future<ModerationResult> _moderateWithLlm(String text) async {
    try {
      final result = await _client!.chatJson(
        model: _bpModel,
        messages: _prompts.moderation(
          scope: _scenario!.contentScope,
          text: text,
          events: _events,
        ),
        temperature: 0.1,
        maxTokens: 120,
      );
      final verdict = parseModerationVerdict(result.json);
      return ModerationResult(
        verdict: verdict,
        category: parseModerationCategory(result.json['category']),
        stage: ModerationStage.llm,
        reason: result.json['reason']?.toString() ?? '',
      );
    } on LlmException {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.none,
        reason: '审核不可用',
      );
    }
  }

  // -------------------------------------------------------------------------
  // 状态与事件
  // -------------------------------------------------------------------------

  Future<void> _emitSegment(String speaker, String text) async {
    // AI 换人说话时，上一条气泡至少停留 2 秒（检定结果 2.5 秒）。
    final previous = state.speaker;
    final aiSwitch =
        previous.isNotEmpty &&
        previous != '你' &&
        speaker != '你' &&
        speaker != previous;
    if (aiSwitch && _lastSegmentAt != null) {
      final isCheckResult =
          _events.isNotEmpty && _events.last.kind == EventKind.checkResult;
      final minDwell = isCheckResult
          ? const Duration(milliseconds: 3500)
          : _minSegmentDwell;
      final elapsed = DateTime.now().difference(_lastSegmentAt!);
      if (elapsed < minDwell) {
        await Future<void>.delayed(minDwell - elapsed);
      }
    }

    if (text.trim().isNotEmpty) _lastUtterance = text.trim();
    _lastSegmentAt = DateTime.now();
    state = state.copyWith(speaker: speaker, segment: text);
  }

  Future<void> _awaitHuman() async {
    if (state.ended) return;
    final scenario = _scenario;
    final scene = _scene;
    final character = _character;
    final client = _client;
    if (scenario == null ||
        scene == null ||
        character == null ||
        client == null) {
      state = state.copyWith(
        status: TableStatus.awaitingInput,
        busy: false,
        interjectReason: '轮到你了',
        suggestions: const <ActionSuggestion>[],
      );
      return;
    }

    // 第一拍：剧本写死的可选动作，不调用 LLM。
    final isFirstBeat = !_events.any(
      (event) => event.kind == EventKind.dialogue,
    );
    if (isFirstBeat && scene.fixedActions.isNotEmpty) {
      state = state.copyWith(
        status: TableStatus.awaitingInput,
        busy: false,
        interjectReason: '轮到你了',
        suggestions: <ActionSuggestion>[
          for (final text in scene.fixedActions) ActionSuggestion(text: text),
        ],
      );
      return;
    }

    // 让 LLM 按当前场景现想 2–4 个动作；生成期间不显示旧建议。
    state = state.copyWith(
      status: TableStatus.playing,
      busy: true,
      interjectReason: '正在整理可选行动',
      suggestions: const <ActionSuggestion>[],
    );
    final suggestions = await _askActionSuggestions(
      scenario: scenario,
      scene: scene,
      character: character,
      client: client,
    );
    if (state.ended) return;
    // 保留上一位说话人：气泡里还是 KP/BP 的话，只把状态切到「等你」。
    state = state.copyWith(
      status: TableStatus.awaitingInput,
      busy: false,
      interjectReason: '轮到你了',
      suggestions: suggestions,
    );
  }

  Future<List<ActionSuggestion>> _askActionSuggestions({
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required LlmClient client,
  }) async {
    try {
      final generator = ref.read(actionSuggesterProvider);
      return await generator(
        client: client,
        model: _kpModel,
        scenario: scenario,
        scene: scene,
        character: character,
        events: _events,
        revealedClues: _revealedClues,
        clocks: _clockValues,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => const <ActionSuggestion>[],
      );
    } catch (_) {
      return const <ActionSuggestion>[];
    }
  }

  void _fail(String code, String message) {
    state = state.copyWith(
      status: TableStatus.error,
      busy: false,
      errorCode: code,
      errorMessage: message,
      interjectReason: '出错了',
    );
  }

  void _markSpoken(String actorId) {
    _lastSpeakerId = actorId;
    for (final actor in _participants) {
      final current = _beatsSince[actor.id] ?? 0;
      _beatsSince[actor.id] = actor.id == actorId ? 0 : current + 1;

      // 每说一拍：说话人清零，其他人按类型涨冲动。
      if (actor.id == actorId) {
        _initiative[actor.id] = 0;
      } else {
        final gain = actor.kind == ActorKind.bp
            ? 2
            : actor.kind == ActorKind.npc
            ? 1
            : 0;
        if (gain > 0) {
          final next = ((_initiative[actor.id] ?? 0) + gain).clamp(0, 10);
          _initiative[actor.id] = next;
        }
      }
    }
    if (actorId == 'human') {
      _beatsSince['human'] = 0;
    }
  }

  void _applyState(KpStateDelta delta) {
    if (delta.isEmpty) return;
    final scene = _scene;
    if (scene != null) {
      final knownClocks = scene.clocks.map((clock) => clock.id).toSet();
      for (final change in delta.clocks) {
        if (!knownClocks.contains(change.id)) continue;
        final max = scene.clocks
            .firstWhere((clock) => clock.id == change.id)
            .max;
        final current = _clockValues[change.id] ?? max;
        final next = current + change.delta;
        _clockValues[change.id] = next < 0 ? 0 : (next > max ? max : next);
      }
    }
    // 线索一旦揭示就进入后续建议，不再依赖开头那三条。
    if (delta.clues.isNotEmpty) _lastDramatic = true;
    _revealedClues.addAll(delta.clues);
    _flags.addAll(delta.flags);
    state = state.copyWith(events: List<GameEvent>.unmodifiable(_events));
  }

  String _rejectionCopy(ModerationResult result) {
    final npc = _scenario?.npcs.isNotEmpty ?? false
        ? _scenario!.npcs.first.name
        : '对方';
    final bp = _scenario != null && _scenario!.bpActors.isNotEmpty
        ? _scenario!.bpActors.first.name
        : '同伴';
    return switch (result.category) {
      ModerationCategory.anachronism => '$npc皱了皱眉：「这话……不像今晚该说的。」',
      ModerationCategory.metaTalk => '$bp低声说：「你刚才那是什么词？」',
      ModerationCategory.tooLong => '这句话太长了，说短一点。',
      ModerationCategory.spam => '别刷屏。',
      _ => '这句话不太适合此刻的场面，换个说法。',
    };
  }

  List<String> _partyNames() {
    final character = _character;
    return <String>[
      character == null || character.name.isEmpty ? '你' : character.name,
      for (final actor in _participants)
        if (actor.kind == ActorKind.bp) actor.name,
      for (final npc in _scenario?.npcs ?? const <ScenarioNpc>[]) npc.name,
    ];
  }

  /// id → 名字，给 KP prompt 显式列出行动者 id，避免它写 player/你。
  Map<String, String> _partyRefs() {
    final character = _character;
    return <String, String>{
      'human': character == null || character.name.isEmpty
          ? '你'
          : character.name,
      for (final actor in _participants)
        if (actor.kind == ActorKind.bp) actor.id: actor.name,
      for (final npc in _scenario?.npcs ?? const <ScenarioNpc>[])
        npc.id: npc.name,
    };
  }

  Set<String> _sceneTags() {
    final scene = _scene;
    if (scene == null) return const <String>{};
    return scene.checks.map((check) => check.label).toSet();
  }

  /// 按对局设置裁剪 BP 数量并命名（默认 1 个，可调；名字可改）。
  Scenario _withConfiguredBp(Scenario scenario, SessionConfig config) {
    final poolSize = scenario.bpActors.length;
    final maxByParty = scenario.partyMax - 1 - scenario.npcs.length;
    final limit = poolSize < maxByParty ? poolSize : maxByParty;
    final count = config.bpCount.clamp(1, limit < 1 ? 1 : limit);

    // 名字语言跟随玩家：中文玩家配中文名，其余配英文名。
    final fallback = pickBpNames(count, playerName: _character?.name ?? '');
    final names = <String>[
      for (var i = 0; i < count; i++)
        i < config.bpNames.length && config.bpNames[i].trim().isNotEmpty
            ? config.bpNames[i].trim()
            : fallback[i],
    ];

    var index = 0;
    final actors = <ScenarioActor>[];
    for (final actor in scenario.actors) {
      if (actor.kind != ActorKindRef.bp) {
        actors.add(actor);
        continue;
      }
      if (index >= count) continue;
      actors.add(
        ScenarioActor(
          id: actor.id,
          kind: actor.kind,
          name: names[index],
          goal: actor.goal,
          secret: actor.secret,
          tags: actor.tags,
          quip: actor.quip,
          switchTrigger: actor.switchTrigger,
        ),
      );
      index++;
    }

    return Scenario(
      id: scenario.id,
      version: scenario.version,
      title: scenario.title,
      subtitle: scenario.subtitle,
      minutes: scenario.minutes,
      rating: scenario.rating,
      partyMax: scenario.partyMax,
      opening: scenario.opening,
      contentScope: scenario.contentScope,
      actors: actors,
      npcs: scenario.npcs,
      scenes: scenario.scenes,
    );
  }

  List<ActorRef> _buildParticipants(Scenario scenario) {
    final character = _character;
    final actorRefs = <ActorRef>[
      ActorRef(
        id: 'human',
        name: character == null || character.name.isEmpty
            ? '你'
            : character.name,
        kind: ActorKind.human,
        tags: <String>{
          for (final skill in Skill.values)
            if (skill.isAllocatable) skill.label,
        },
      ),
    ];
    for (final actor in scenario.actors) {
      if (actor.kind != ActorKindRef.bp) continue;
      actorRefs.add(
        ActorRef(
          id: actor.id,
          name: actor.name,
          kind: ActorKind.bp,
          tags: actor.tags,
        ),
      );
    }
    for (final npc in scenario.npcs) {
      actorRefs.add(
        ActorRef(
          id: npc.id,
          name: npc.name,
          kind: ActorKind.npc,
          tags: npc.tags,
        ),
      );
    }
    return actorRefs;
  }

  GameEvent _event(
    String kind,
    Audience audience, {
    String? actorId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    _seq += 1;
    return GameEvent(
      seq: _seq,
      kind: kind,
      audience: audience,
      actorId: actorId,
      sceneId: _sceneId,
      beat: _seq,
      payload: payload,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _append(List<GameEvent> events) async {
    _events.addAll(events);
    final store = _store;
    if (store != null && state.sessionId.isNotEmpty) {
      await store.appendAll(state.sessionId, events);
    }
    state = state.copyWith(
      events: List<GameEvent>.unmodifiable(List<GameEvent>.from(_events)),
    );
  }
}

enum _BeatOutcome { ai, human, stop }
