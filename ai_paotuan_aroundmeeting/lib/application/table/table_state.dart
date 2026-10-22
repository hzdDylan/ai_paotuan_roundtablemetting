import '../../engine/knowledge/game_event.dart';
import '../../engine/rules/check.dart';
import '../../engine/turn/action_suggestion.dart';

enum TableStatus { idle, loading, playing, awaitingInput, ended, error }

const Object _keep = Object();

/// 桌面的不可变视图状态。
///
/// 这是 application 与 presentation 的契约：会话只更新它，UI 只读它。
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
  final int partySize;
  final String? inputRejected;
  final bool ended;

  /// 本局实际使用的 BP 名字（已按对局设置改名）。
  final List<String> bpNames;

  /// 由 LLM 根据当前场景生成的建议行动。
  final List<ActionSuggestion> suggestions;

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
    partySize: partySize ?? this.partySize,
    inputRejected: identical(inputRejected, _keep)
        ? this.inputRejected
        : inputRejected as String?,
    ended: ended ?? this.ended,
    suggestions: suggestions ?? this.suggestions,
    bpNames: bpNames ?? this.bpNames,
  );
}
