/// 一局开始前的玩家配置：AI 玩家数量与名字。
class SessionConfig {
  const SessionConfig({this.bpCount = 1, this.bpNames = const <String>[]});

  final int bpCount;
  final List<String> bpNames;

  SessionConfig copyWith({int? bpCount, List<String>? bpNames}) =>
      SessionConfig(
        bpCount: bpCount ?? this.bpCount,
        bpNames: bpNames ?? this.bpNames,
      );
}
