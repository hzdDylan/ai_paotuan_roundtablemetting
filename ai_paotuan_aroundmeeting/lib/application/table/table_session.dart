import 'dart:async';

import '../../engine/archive/archive_record.dart';
import '../../engine/dice/dice.dart';
import '../../engine/director/director.dart';
import '../../engine/knowledge/audience.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/knowledge/knowledge_filter.dart';
import '../../engine/moderation/moderation.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/turn/action_suggestion.dart';
import '../../engine/turn/actor_turn.dart';
import '../../engine/turn/kp_turn.dart';
import '../ports/app_failure.dart';
import '../ports/archive_repository.dart';
import '../ports/clock.dart';
import '../ports/event_store.dart';
import '../ports/llm_gateway.dart';
import 'check_flow.dart';
import 'check_resolver.dart';
import 'event_recorder.dart';
import 'scene_state.dart';
import 'session_bootstrap.dart';
import 'session_config.dart';
import 'table_state.dart';

/// 一局游戏的命令外壳。
///
/// 职责：驱动一次开局 / 一拍 / 一次提交 / 归档，维护局内可变状态。
/// 纯计算（规则、Director、场景条件）留在 engine；I/O 通过端口注入。
final class TableSession {
  TableSession({
    required Scenario scenario,
    required CharacterSheet character,
    required SessionConfig config,
    required LlmGateway llm,
    required EventStore eventStore,
    required ArchiveRepository archives,
    required Clock clock,
    required RngPort rng,
    required Director director,
    SessionBootstrap bootstrap = const SessionBootstrap(),
  }) : _sourceScenario = scenario,
       _character = character,
       _config = config,
       _llm = llm,
       _archives = archives,
       _clock = clock,
       _director = director,
       _bootstrap = bootstrap,
       _recorder = EventRecorder(store: eventStore, clock: clock) {
    _checkFlow = CheckFlow(
      llm: llm,
      resolver: CheckResolver(rng: rng),
      recorder: _recorder,
    );
  }

  final Scenario _sourceScenario;
  final CharacterSheet _character;
  final SessionConfig _config;
  final LlmGateway _llm;
  final ArchiveRepository _archives;
  final Clock _clock;
  final Director _director;
  final SessionBootstrap _bootstrap;
  late final CheckFlow _checkFlow;

  final StreamController<TableState> _updates =
      StreamController<TableState>.broadcast(sync: true);
  final EventRecorder _recorder;
  final Map<String, int> _beatsSince = <String, int>{};
  final Map<String, int> _initiative = <String, int>{};

  TableState _state = const TableState();
  SceneState? _sceneState;
  Scenario? _scenario;
  List<ActorRef> _participants = const <ActorRef>[];
  LocalModerator? _moderator;

  String? _lastSpeakerId;
  String _lastUtterance = '';
  bool _lastDramatic = false;
  bool _forceBpAfterFail = false;
  int _lastSideChatSeq = -99;
  DateTime? _lastSegmentAt;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _closed = false;

  TableState get state => _state;

  Stream<TableState> get updates => _updates.stream;

  SceneDef? get _scene => _sceneState?.scene;

  List<GameEvent> get _events => _recorder.events;

  List<Roll> get _rolls => _recorder.rolls;

  Set<String> get _flags => _sceneState?.flags ?? const <String>{};

  Set<String> get _revealedClues => _sceneState?.clues ?? const <String>{};

  Map<String, int> get _clockValues =>
      _sceneState?.clocks ?? const <String, int>{};

  String get _sceneId => _sceneState?.sceneId ?? '';

  // -------------------------------------------------------------------------
  // 命令
  // -------------------------------------------------------------------------

  Future<void> start() => _guard(() async {
    _setState(
      _state.copyWith(
        status: TableStatus.loading,
        busy: true,
        segment: '',
        errorCode: null,
        errorMessage: null,
        inputRejected: null,
        ended: false,
      ),
    );

    final boot = _bootstrap.build(
      scenario: _sourceScenario,
      character: _character,
      config: _config,
    );
    final scenario = boot.scenario;
    final scene = boot.scene;

    _scenario = scenario;
    _sceneState = SceneState(scene);
    _participants = boot.participants;
    _moderator = LocalModerator(scope: scenario.contentScope);
    _startedAt = _clock.now();
    final sessionId = 'sess_${_startedAt.millisecondsSinceEpoch}';
    _recorder.reset(sessionId: sessionId, sceneId: scene.id);

    _forceBpAfterFail = false;
    _initiative.clear();
    _lastUtterance = '';
    _lastDramatic = false;
    _lastSideChatSeq = -99;
    _lastSegmentAt = null;
    _beatsSince.clear();
    _lastSpeakerId = null;

    _setState(
      _state.copyWith(
        status: TableStatus.playing,
        sessionId: sessionId,
        scenarioId: scenario.id,
        sceneName: scene.name,
        partySize: scenario.partySize,
        bpNames: boot.bpNames,
        busy: true,
        speaker: 'KP',
        events: const <GameEvent>[],
        suggestions: const <ActionSuggestion>[],
      ),
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
    if (!_state.ended) await _awaitHuman();
  });

  Future<void> advance() async {
    if (_state.busy || _state.ended) return;
    _setState(_state.copyWith(busy: true));
    await _guard(() => _advanceUntilHuman(maxSteps: 2));
  }

  Future<void> submitPlayer(String raw, {String? checkHint}) async {
    final text = raw.trim();
    if (text.isEmpty || _state.busy || _state.ended) return;

    final moderator = _moderator;
    if (moderator == null) return;

    // 提交后立即收起选项与输入，直到下一个「我的回合」。
    _setState(
      _state.copyWith(
        status: TableStatus.playing,
        busy: true,
        inputRejected: null,
      ),
    );

    await _guard(() async {
      var result = moderator.check(text);
      if (result.needsLlm) {
        result = await _llm.moderate(
          scenario: _scenario!,
          text: text,
          events: _eventsForHuman(),
        );
      }
      if (!result.passes) {
        _setState(
          _state.copyWith(
            busy: false,
            status: TableStatus.awaitingInput,
            inputRejected: _rejectionCopy(result),
          ),
        );
        return;
      }

      final human = _humanActor();
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
    });
  }

  /// 自动归档（D-24 / V-21：玩家不触发、不感知）。
  Future<ArchiveRecord?> endAndArchive({
    String endingId = 'auto',
    String endingTitle = '本局结束',
  }) async {
    if (_state.sessionId.isEmpty || _state.ended) return null;
    final scenario = _scenario;
    if (scenario == null) return null;

    try {
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

      final record = await _archives.seal(
        sessionId: _state.sessionId,
        scenario: scenario,
        character: _character,
        events: _events,
        rolls: _rolls,
        startedAt: _startedAt,
        endingId: endingId,
        endingTitle: endingTitle,
        oneLine: oneLine,
        review: review,
      );

      _setState(
        _state.copyWith(
          status: TableStatus.ended,
          ended: true,
          busy: false,
          segment: review.isEmpty ? null : review,
          speaker: review.isEmpty ? null : 'KP',
        ),
      );
      return record;
    } on AppFailure catch (error) {
      _fail(error.code, error.message);
      return null;
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
      return null;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _updates.close();
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

    final kp = await _llm.kpTurn(
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

    // 只有「玩家普通失败」强制 BP 救场；其余交给冲动值决定谁开口。
    final needBp = _forceBpAfterFail;
    _forceBpAfterFail = false;

    if (needBp && bps.isNotEmpty && !_state.ended) {
      await _runBp(bps.first);
      if (_state.ended) return;
    }

    for (var step = 0; step < maxSteps; step++) {
      if (_state.ended) return;
      final outcome = await _runOneBeat();
      if (outcome == _BeatOutcome.human || _state.ended) break;
    }
    if (!_state.ended) await _awaitHuman();
  }

  Future<_BeatOutcome> _runOneBeat() async {
    final allowSideChat = _recorder.seq - _lastSideChatSeq >= 5;
    final pick = _director.pick(
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
        _lastSideChatSeq = _recorder.seq;
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

    _setState(_state.copyWith(busy: true));

    final turn = await _llm.bpTurn(
      scenario: scenario,
      scene: scene,
      actor: def,
      events: _eventsFor(actor),
      others: _partyNames().where((name) => name != actor.name).toList(),
      lastSpeaker: _lastSpeakerId,
      sideChatTo: sideChatTarget?.name,
    );
    await _applyBpTurn(actor, turn);
  }

  Future<void> _applyBpTurn(ActorRef actor, ActorTurn turn) async {
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

    final declaration = await _llm.kpTurn(
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
    final decl =
        declaration.check ??
        CheckDecl(
          actorId: actor.id,
          skill: skill,
          difficulty: Difficulty.regular,
          stakes: '',
        );

    await _rollAndNarrate(decls: <CheckDecl>[decl]);
  }

  /// 掷骰 → 落库/展示 → KP 统一叙述（一个动作或多动作共用）。
  Future<void> _rollAndNarrate({required List<CheckDecl> decls}) async {
    final scenario = _scenario!;
    final scene = _scene!;
    final result = await _checkFlow.run(
      decls: decls,
      scenario: scenario,
      scene: scene,
      character: _character,
      participants: _participants,
      events: _events,
      actorNames: _actorNames(),
    );

    _lastDramatic = _lastDramatic || result.dramatic;
    _forceBpAfterFail = _forceBpAfterFail || result.humanFailed;
    _setState(_state.copyWith(dice: result.rolls.last));
    await _append(result.events);
    await _emitSegment('KP', result.narration.displayText);
    _applyState(result.narration.state);
    if (result.fatalFumble != null) {
      await _applyFatalFumble(result.fatalFumble!);
      return;
    }
    await _handleSignal(result.narration.signal, result.narration.nextSceneId);
  }

  Future<void> _runKpRespond(
    ActorRef actor, {
    required String instruction,
  }) async {
    final scenario = _scenario!;
    final scene = _scene!;

    _setState(_state.copyWith(busy: true));

    final kp = await _llm.kpTurn(
      scenario: scenario,
      scene: scene,
      events: _events,
      party: _partyRefs(),
      instruction: instruction,
      flags: _flags,
      revealedClues: _revealedClues,
      clocks: _clockValues,
    );
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

    await _rollAndNarrate(decls: checks);

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
    if (_state.ended || _state.sessionId.isEmpty) return true;

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

  String? _clockZeroTarget() => _sceneState?.clockZeroTarget();

  /// 只接受「当前场景确实有、且条件已满足」的出口；防止 KP 硬跳。
  String? _validatedExit(String? requested) =>
      _sceneState?.validatedExit(requested);

  String? _firstOpenExit() => _sceneState?.firstOpenExit();

  Future<void> _moveToScene(String sceneId) async {
    final scenario = _scenario;
    final sceneState = _sceneState;
    if (scenario == null || sceneState == null || _state.ended) return;
    if (sceneId == _sceneId) return;

    final next = scenario.sceneById(sceneId);
    if (next == null) return;

    await _append(<GameEvent>[
      _event(
        EventKind.sceneEnd,
        const Audience.public(),
        payload: <String, dynamic>{'scene': sceneState.sceneId},
      ),
    ]);

    sceneState.enter(next);
    _recorder.setSceneId(next.id);
    _beatsSince.clear();
    _lastSpeakerId = null;

    _setState(
      _state.copyWith(
        sceneName: next.name,
        suggestions: const <ActionSuggestion>[],
      ),
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

  Future<String> _buildReview(String endingTitle) async {
    final scenario = _scenario;
    if (scenario == null) return _fallbackReview(endingTitle);
    try {
      final text = await _llm.review(
        scenario: scenario,
        endingTitle: endingTitle,
        characterName: _character.name.isEmpty ? '你' : _character.name,
        events: _events,
        rolls: _rolls,
      );
      if (text.isNotEmpty) return text;
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
  // 状态与事件
  // -------------------------------------------------------------------------

  Future<void> _emitSegment(String speaker, String text) async {
    // AI 换人说话时，上一条气泡至少停留 2 秒（检定结果 2.5 秒）。
    final previous = _state.speaker;
    final aiSwitch =
        previous.isNotEmpty &&
        previous != '你' &&
        speaker != '你' &&
        speaker != previous;
    if (aiSwitch && _lastSegmentAt != null) {
      const minDwell = Duration(milliseconds: 3500);
      final elapsed = _clock.now().difference(_lastSegmentAt!);
      if (elapsed < minDwell) {
        await Future<void>.delayed(minDwell - elapsed);
      }
    }

    if (text.trim().isNotEmpty) _lastUtterance = text.trim();
    _lastSegmentAt = _clock.now();
    _setState(_state.copyWith(speaker: speaker, segment: text));
  }

  Future<void> _awaitHuman() async {
    if (_state.ended) return;
    final scenario = _scenario;
    final scene = _scene;
    if (scenario == null || scene == null) {
      _setState(
        _state.copyWith(
          status: TableStatus.awaitingInput,
          busy: false,
          suggestions: const <ActionSuggestion>[],
        ),
      );
      return;
    }

    // 第一拍：剧本写死的可选动作，不调用 LLM。
    final isFirstBeat = !_events.any(
      (event) => event.kind == EventKind.dialogue,
    );
    if (isFirstBeat && scene.fixedActions.isNotEmpty) {
      _setState(
        _state.copyWith(
          status: TableStatus.awaitingInput,
          busy: false,
          suggestions: <ActionSuggestion>[
            for (final text in scene.fixedActions) ActionSuggestion(text: text),
          ],
        ),
      );
      return;
    }

    // 让 LLM 按当前场景现想 2–4 个动作；生成期间不显示旧建议。
    _setState(
      _state.copyWith(
        status: TableStatus.playing,
        busy: true,
        suggestions: const <ActionSuggestion>[],
      ),
    );
    final suggestions = await _llm.suggestions(
      scenario: scenario,
      scene: scene,
      character: _character,
      events: _eventsForHuman(),
      revealedClues: _revealedClues,
      clocks: _clockValues,
    );
    if (_state.ended) return;
    // 保留上一位说话人：气泡里还是 KP/BP 的话，只把状态切到「等你」。
    _setState(
      _state.copyWith(
        status: TableStatus.awaitingInput,
        busy: false,
        suggestions: suggestions,
      ),
    );
  }

  void _fail(String code, String message) {
    _setState(
      _state.copyWith(
        status: TableStatus.error,
        busy: false,
        errorCode: code,
        errorMessage: message,
      ),
    );
  }

  void _markSpoken(String actorId) {
    _lastSpeakerId = actorId;
    for (final actor in _participants) {
      final current = _beatsSince[actor.id] ?? 0;
      _beatsSince[actor.id] = actor.id == actorId ? 0 : current + 1;

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
    if (delta.clues.isNotEmpty) _lastDramatic = true;
    _sceneState?.apply(delta);
    _setState(_state.copyWith(events: List<GameEvent>.unmodifiable(_events)));
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

  ActorRef _humanActor() {
    for (final actor in _participants) {
      if (actor.kind == ActorKind.human) return actor;
    }
    return ActorRef(
      id: 'human',
      name: _character.name.isEmpty ? '你' : _character.name,
      kind: ActorKind.human,
    );
  }

  List<String> _partyNames() => <String>[
    _character.name.isEmpty ? '你' : _character.name,
    for (final actor in _participants)
      if (actor.kind == ActorKind.bp) actor.name,
    for (final npc in _scenario?.npcs ?? const <ScenarioNpc>[]) npc.name,
  ];

  /// id → 名字，给 KP prompt 显式列出行动者 id，避免它写 player/你。
  Map<String, String> _partyRefs() => <String, String>{
    'human': _character.name.isEmpty ? '你' : _character.name,
    for (final actor in _participants)
      if (actor.kind == ActorKind.bp) actor.id: actor.name,
    for (final npc in _scenario?.npcs ?? const <ScenarioNpc>[])
      npc.id: npc.name,
  };

  Map<String, String> _actorNames() => <String, String>{
    'human': _character.name.isEmpty ? '你' : _character.name,
    for (final actor in _participants) actor.id: actor.name,
    for (final npc in _scenario?.npcs ?? const <ScenarioNpc>[])
      npc.id: npc.name,
  };

  Set<String> _sceneTags() {
    final scene = _scene;
    if (scene == null) return const <String>{};
    return scene.checks.map((check) => check.label).toSet();
  }

  /// 只把该行动者可见的事件交给 Prompt，落实 D-07 知识边界。
  List<GameEvent> _eventsFor(ActorRef actor) => const KnowledgeFilter().window(
    Viewer(id: actor.id, kind: actor.kind),
    _events,
  );

  List<GameEvent> _eventsForHuman() => const KnowledgeFilter().window(
    const Viewer(id: 'human', kind: ActorKind.human),
    _events,
  );

  GameEvent _event(
    String kind,
    Audience audience, {
    String? actorId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) => _recorder.make(kind, audience, actorId: actorId, payload: payload);

  Future<void> _append(List<GameEvent> events) async {
    await _recorder.append(events);
    _setState(
      _state.copyWith(events: List<GameEvent>.unmodifiable(_recorder.events)),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AppFailure catch (error) {
      if (error.code == 'E_CANCELLED') {
        _setState(_state.copyWith(busy: false));
        return;
      }
      _fail(error.code, error.message);
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
    }
  }

  void _setState(TableState next) {
    if (_closed) return;
    _state = next;
    _updates.add(next);
  }
}

enum _BeatOutcome { ai, human, stop }
