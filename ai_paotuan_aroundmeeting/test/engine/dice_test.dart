import 'package:ai_paotuan_aroundmeeting/engine/dice/dice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rollDie 把 0–99 映射到 1–100', () {
    final rng = SequenceRng([0, 99, 50]);
    expect(rollDie(rng), 1);
    expect(rollDie(rng), 100);
    expect(rollDie(rng), 51);
  });

  test('SequenceRng 循环使用序列', () {
    final rng = SequenceRng([1, 2]);
    expect(rng.nextInt(10), 1);
    expect(rng.nextInt(10), 2);
    expect(rng.nextInt(10), 1);
  });

  test('SecureRng 覆盖 1–100 且不越界', () {
    final rng = SecureRng();
    final seen = <int>{};
    for (var i = 0; i < 20000; i++) {
      final die = rollDie(rng);
      expect(die, inInclusiveRange(1, 100));
      seen.add(die);
    }
    // 2 万次仍缺某一面的概率极低（约 100 × e^-200），可作为冒烟断言。
    expect(seen.length, 100);
  });
}
