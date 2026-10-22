import 'dart:math';

/// 随机源端口（SE §3.4）。
///
/// 领域层只认这个接口：测试可以注入固定序列，生产用 [SecureRng]。
/// 骰值只能由 [rollDie] 产生，别处没有入口能造出一个 `Roll`。
abstract interface class RngPort {
  /// 返回 `[0, max)` 的整数。
  int nextInt(int max);
}

/// 生产实现：系统安全随机。
///
/// 不是为了防作弊，而是避免同一毫秒内多次开局落到同一条伪随机序列上。
class SecureRng implements RngPort {
  SecureRng() : _random = Random.secure();

  final Random _random;

  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// 测试用：按给定序列循环返回。
class SequenceRng implements RngPort {
  SequenceRng(List<int> values)
    : assert(values.isNotEmpty, 'SequenceRng 至少需要一个值'),
      _values = List<int>.unmodifiable(values);

  final List<int> _values;
  int _cursor = 0;

  @override
  int nextInt(int max) {
    final value = _values[_cursor % _values.length];
    _cursor++;
    return value % max;
  }
}

/// 掷一颗 d100：1–100（含 100）。
int rollDie(RngPort rng) => rng.nextInt(100) + 1;
