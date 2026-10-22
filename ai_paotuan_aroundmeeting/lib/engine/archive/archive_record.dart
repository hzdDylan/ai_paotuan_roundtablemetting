/// 归档摘要（列表页用）。
class ArchiveRecord {
  const ArchiveRecord({
    required this.sessionId,
    required this.scenarioTitle,
    required this.endingTitle,
    required this.beatCount,
    required this.partySize,
    required this.endedAt,
    required this.path,
    this.oneLine = '',
    this.lastRoll = '',
    this.review = '',
  });

  final String sessionId;
  final String scenarioTitle;
  final String endingTitle;
  final int beatCount;
  final int partySize;
  final DateTime endedAt;
  final String path;

  /// 结局一句话（取最后一拍叙述）。
  final String oneLine;

  /// 最后一骰的可读描述，如「话术 48 成功」。
  final String lastRoll;

  /// KP 对本局的复盘评价。
  final String review;

  bool get isValid => sessionId.isNotEmpty;
}
