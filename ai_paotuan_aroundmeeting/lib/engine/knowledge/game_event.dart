import 'audience.dart';

/// 事件类型（SE §5.2）。
abstract final class EventKind {
  static const sessionStart = 'session_start';
  static const sceneStart = 'scene_start';
  static const narration = 'narration';
  static const dialogue = 'dialogue';
  static const action = 'action';
  static const checkDeclared = 'check_declared';
  static const roll = 'roll';
  static const checkResult = 'check_result';
  static const stateDelta = 'state_delta';
  static const inputAllowed = 'input_allowed';
  static const inputRejected = 'input_rejected';
  static const sceneEnd = 'scene_end';
  static const sessionEnd = 'session_end';
  static const systemError = 'system_error';
}

/// 一条不可变事件。排序一律以 [seq] 为准，时间戳只作展示。
class GameEvent {
  const GameEvent({
    required this.seq,
    required this.kind,
    required this.audience,
    this.actorId,
    this.sceneId,
    this.beat = 0,
    this.payload = const <String, dynamic>{},
    this.createdAt = 0,
  });

  final int seq;
  final String kind;
  final Audience audience;
  final String? actorId;
  final String? sceneId;
  final int beat;
  final Map<String, dynamic> payload;
  final int createdAt;

  /// 便于记录页/测试取用。
  String get text =>
      (payload['text'] as String?) ??
      (payload['line'] as String?) ??
      (payload['narration'] as String?) ??
      '';

  GameEvent copyWith({
    int? seq,
    String? kind,
    Audience? audience,
    String? actorId,
    String? sceneId,
    int? beat,
    Map<String, dynamic>? payload,
    int? createdAt,
  }) => GameEvent(
    seq: seq ?? this.seq,
    kind: kind ?? this.kind,
    audience: audience ?? this.audience,
    actorId: actorId ?? this.actorId,
    sceneId: sceneId ?? this.sceneId,
    beat: beat ?? this.beat,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'kind': kind,
    'audience': audience.toTag(),
    if (actorId != null) 'actor': actorId,
    if (sceneId != null) 'scene': sceneId,
    'beat': beat,
    'payload': payload,
    'created_at': createdAt,
  };

  factory GameEvent.fromJson(Map<String, dynamic> json) => GameEvent(
    seq: (json['seq'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? '',
    audience: Audience.fromTag(json['audience'] as String? ?? 'public'),
    actorId: json['actor'] as String?,
    sceneId: json['scene'] as String?,
    beat: (json['beat'] as num?)?.toInt() ?? 0,
    payload: Map<String, dynamic>.from(
      json['payload'] as Map? ?? const <String, dynamic>{},
    ),
    createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
  );
}
