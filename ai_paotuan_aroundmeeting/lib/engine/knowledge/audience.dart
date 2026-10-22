/// 事件可见性（SE §3.5）。秘密在拼 prompt 之前就被裁掉，而不是靠措辞约束。
enum AudienceKind { public, kp, party, private }

/// 谁看得见这条事件。
///
/// - [Audience.public]：桌面上公开发生的事
/// - [Audience.kpOnly]：只有守秘人知道的剧本事实
/// - [Audience.party]：玩家阵营（真人 + BP）共享的线索
/// - [Audience.privateTo]：某个角色的秘密 / 内心
class Audience {
  const Audience._(this.kind, this.actorId);

  const Audience.public() : this._(AudienceKind.public, null);

  const Audience.kpOnly() : this._(AudienceKind.kp, null);

  const Audience.party() : this._(AudienceKind.party, null);

  const Audience.privateTo(String actorId)
    : this._(AudienceKind.private, actorId);

  final AudienceKind kind;

  /// 仅 [AudienceKind.private] 时有值。
  final String? actorId;

  /// 落盘用的标签：`public` / `kp` / `party` / `private:bp_stella`。
  String toTag() => switch (kind) {
    AudienceKind.public => 'public',
    AudienceKind.kp => 'kp',
    AudienceKind.party => 'party',
    AudienceKind.private => 'private:$actorId',
  };

  static Audience fromTag(String tag) {
    if (tag == 'public') return const Audience.public();
    if (tag == 'kp') return const Audience.kpOnly();
    if (tag == 'party') return const Audience.party();
    if (tag.startsWith('private:')) {
      return Audience.privateTo(tag.substring('private:'.length));
    }
    throw ArgumentError.value(tag, 'tag', '未知的 audience 标签');
  }
}
