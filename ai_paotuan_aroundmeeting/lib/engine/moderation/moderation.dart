/// 玩家输入审核（SE §3.9，D-28 = B：本地规则先筛，不确定才交 LLM）。
library;

/// 剧本边界：审核判据的来源，由剧本 YAML 的 `content_scope` 提供。
class ContentScope {
  const ContentScope({
    this.era = '',
    this.genre = '',
    this.rating = '',
    this.allowed = const <String>[],
    this.forbidden = const <String>[],
    this.intent = '',
  });

  factory ContentScope.fromJson(Map<String, dynamic> json) => ContentScope(
    era: json['era'] as String? ?? '',
    genre: json['genre'] as String? ?? '',
    rating: json['rating'] as String? ?? '',
    allowed: _stringList(json['allowed']),
    forbidden: _stringList(json['forbidden']),
    intent: json['intent'] as String? ?? '',
  );

  final String era;
  final String genre;
  final String rating;
  final List<String> allowed;
  final List<String> forbidden;
  final String intent;

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  /// 给 LLM 审核 prompt 用的边界摘要。
  String toPromptBlock() => [
    if (era.isNotEmpty) '时代：$era',
    if (genre.isNotEmpty) '题材：$genre',
    if (rating.isNotEmpty) '分级：$rating',
    if (allowed.isNotEmpty) '允许：${allowed.join('、')}',
    if (forbidden.isNotEmpty) '禁止：${forbidden.join('、')}',
    if (intent.isNotEmpty) '要求：$intent',
  ].join('\n');

  bool get isEmpty =>
      era.isEmpty &&
      genre.isEmpty &&
      rating.isEmpty &&
      allowed.isEmpty &&
      forbidden.isEmpty &&
      intent.isEmpty;
}

/// 审核结论。
enum ModerationVerdict {
  /// 放行。
  allow,

  /// 驳回（本地硬规则命中）。
  reject,

  /// 本地判不了，需要交 LLM。
  uncertain,
}

/// 驳回类别（进 metadata，用来调词表）。
enum ModerationCategory {
  none,
  spam,
  tooLong,
  illegal,
  sexual,
  minor,
  violence,
  metaTalk,
  anachronism,
}

/// 审核发生在哪一级。
enum ModerationStage { local, llm }

/// 审核结果。
class ModerationResult {
  const ModerationResult({
    required this.verdict,
    this.category = ModerationCategory.none,
    this.stage = ModerationStage.local,
    this.reason = '',
  });

  final ModerationVerdict verdict;
  final ModerationCategory category;
  final ModerationStage stage;

  /// 给日志看的原因（不进 transcript、不存原文）。
  final String reason;

  bool get passes => verdict == ModerationVerdict.allow;

  bool get needsLlm => verdict == ModerationVerdict.uncertain;

  @override
  String toString() =>
      'ModerationResult(${verdict.name}, ${category.name}, ${reason.isEmpty ? '-' : reason})';
}

/// 本地审核：形式校验 + 硬词表 + 出戏检测。
///
/// 设计原则：
/// - 只拦「确定不能过」的，模糊的交 LLM（避免误杀）；
/// - 「离谱但不出戏」必须放行——那正是这个游戏的乐趣。
class LocalModerator {
  const LocalModerator({required this.scope, this.maxLength = 200});

  final ContentScope scope;
  final int maxLength;

  /// 明确违法：直接驳回。
  static const List<String> _illegalWords = <String>[
    '制毒',
    '制爆',
    '改装枪支',
    '走私毒品',
  ];

  /// 露骨性内容：直接驳回。
  static const List<String> _sexualWords = <String>['性行为', '强奸', '色情'];

  /// 未成年人相关：直接驳回。
  static const List<String> _minorWords = <String>['未成年', '幼童', '儿童色情'];

  /// 虐待细节 / 极端暴力：直接驳回。
  static const List<String> _violenceWords = <String>['肢解', '酷刑', '虐杀', '虐待细节'];

  /// 出戏的元话语：直接驳回。
  static const List<String> _metaTalkWords = <String>[
    '我是AI',
    '作为AI',
    '系统提示',
    '提示词',
    '语言模型',
  ];

  /// 现代科技 / 现代梗：本地无法确定是否为玩家刻意的玩笑 → 交 LLM。
  static const List<String> _anachronismWords = <String>[
    '手机',
    '电脑',
    '互联网',
    '百度',
    '微信',
    'WiFi',
    'wifi',
    '短视频',
    '直播带货',
  ];

  ModerationResult check(String input) {
    final text = input.trim();

    if (text.isEmpty) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.spam,
        reason: '空输入',
      );
    }

    if (text.length > maxLength) {
      return ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.tooLong,
        reason: '超过 $maxLength 字',
      );
    }

    if (_looksLikeSpam(text)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.spam,
        reason: '重复刷屏',
      );
    }

    if (_containsAny(text, _metaTalkWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.metaTalk,
        reason: '出戏元话语',
      );
    }

    if (_containsAny(text, _illegalWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.illegal,
        reason: '违法内容',
      );
    }

    if (_containsAny(text, _sexualWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.sexual,
        reason: '露骨性内容',
      );
    }

    if (_containsAny(text, _minorWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.minor,
        reason: '未成年人相关',
      );
    }

    if (_containsAny(text, _violenceWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.violence,
        reason: '虐待/极端暴力',
      );
    }

    if (_containsAny(text, _anachronismWords)) {
      return const ModerationResult(
        verdict: ModerationVerdict.uncertain,
        category: ModerationCategory.anachronism,
        reason: '疑似出戏，交 LLM 判定',
      );
    }

    return const ModerationResult(verdict: ModerationVerdict.allow);
  }

  bool _containsAny(String text, List<String> words) =>
      words.any(text.contains);

  /// 「哈哈哈哈哈哈」「。。。」这类算刷屏。
  bool _looksLikeSpam(String text) {
    if (text.length < 6) return false;
    final unique = text.runes.toSet();
    return unique.length <= 2;
  }
}
