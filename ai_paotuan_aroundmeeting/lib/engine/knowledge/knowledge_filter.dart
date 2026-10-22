import '../director/director.dart';
import 'audience.dart';
import 'game_event.dart';

/// 观察者：某个角色 / KP，用 `id + kind` 表达。
class Viewer {
  const Viewer({required this.id, required this.kind});

  final String id;
  final ActorKind kind;

  bool get isKp => kind == ActorKind.kp;
  bool get isNpc => kind == ActorKind.npc;
}

/// 知识边界：决定「谁能看见哪条事件」（SE §3.5，D-07 = A）。
///
/// 关键点：过滤发生在**拼 prompt 之前**，不是写在 prompt 里求模型别说。
class KnowledgeFilter {
  const KnowledgeFilter();

  bool canSee(Viewer viewer, Audience audience) {
    if (viewer.isKp) return true;
    return switch (audience.kind) {
      AudienceKind.public => true,
      AudienceKind.kp => false,
      AudienceKind.party => !viewer.isNpc,
      AudienceKind.private => audience.actorId == viewer.id,
    };
  }

  List<GameEvent> visibleTo(Viewer viewer, Iterable<GameEvent> events) => events
      .where((event) => canSee(viewer, event.audience))
      .toList(growable: false);

  /// 滑窗（D-18 = A）：只取最近 [limit] 条可见事件。
  List<GameEvent> window(
    Viewer viewer,
    Iterable<GameEvent> events, {
    int limit = 40,
  }) {
    final visible = visibleTo(viewer, events);
    if (visible.length <= limit) return visible;
    return visible.sublist(visible.length - limit);
  }

  /// 测试/调试用：把某个观察者能看到的全部文本拼起来，
  /// 用来断言「不含别人的秘密」。
  String debugCorpus(Viewer viewer, Iterable<GameEvent> events) =>
      visibleTo(viewer, events).map((event) => event.text).join('\n');
}
