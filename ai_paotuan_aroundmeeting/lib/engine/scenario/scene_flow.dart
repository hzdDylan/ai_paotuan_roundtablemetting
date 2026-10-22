import '../rules/check.dart';
import 'scenario.dart';

/// 场景出口条件（剧本 YAML 的 `when`）。
///
/// 支持：
/// - 空 / `always`：随时可走；
/// - `flag:xxx`：已获得标记；
/// - `clue:xxx`：已揭示线索；
/// - `clock_zero:xxx`：该时钟归零；
/// - `!` 取反，`&&` 同时满足，`||` 任一满足。
///
/// 条件只读状态，不改状态，方便单测与审查。
bool isExitOpen(
  SceneExit exit, {
  required Set<String> flags,
  required Set<String> clues,
  required Map<String, int> clocks,
}) => isConditionOpen(exit.when, flags: flags, clues: clues, clocks: clocks);

/// 通用条件判断：出口和建议行动共用同一套语法。
bool isConditionOpen(
  String when, {
  required Set<String> flags,
  required Set<String> clues,
  required Map<String, int> clocks,
}) {
  final raw = when.trim();
  if (raw.isEmpty || raw == 'always') return true;

  return raw.split('||').any((group) {
    return group
        .split('&&')
        .every(
          (term) => _evalTerm(
            term.trim(),
            flags: flags,
            clues: clues,
            clocks: clocks,
          ),
        );
  });
}

bool _evalTerm(
  String raw, {
  required Set<String> flags,
  required Set<String> clues,
  required Map<String, int> clocks,
}) {
  var term = raw;
  var negate = false;
  while (term.startsWith('!')) {
    negate = !negate;
    term = term.substring(1).trim();
  }
  if (term.isEmpty) return false;

  final value = switch (term) {
    _ when term.startsWith('flag:') => flags.contains(term.substring(5)),
    _ when term.startsWith('clue:') => clues.contains(term.substring(5)),
    _ when term.startsWith('clock_zero:') =>
      (clocks[term.substring(11)] ?? 0) <= 0,
    _ => false,
  };
  return negate ? !value : value;
}

/// 只对玩家的大失败生效；BP 的大失败不替玩家结束整局。
SceneFumble? fatalFumbleFor(SceneDef scene, Roll roll, String actorId) {
  if (actorId != 'human' || roll.outcome != Outcome.fumble) return null;
  for (final check in scene.checks) {
    if (check.label == roll.label && check.onFumble != null) {
      return check.onFumble;
    }
  }
  return null;
}

/// 把条件翻译成 KP 能读懂的中文；未知条件原样返回，便于发现剧本写错。
String describeExitCondition(String when) {
  final raw = when.trim();
  if (raw.isEmpty || raw == 'always') return '随时';
  return raw
      .split('||')
      .map((group) {
        return group
            .split('&&')
            .map((term) => _describeTerm(term.trim()))
            .join(' 且 ');
      })
      .join(' 或 ');
}

String _describeTerm(String term) {
  var text = term;
  var negate = false;
  while (text.startsWith('!')) {
    negate = !negate;
    text = text.substring(1).trim();
  }
  final label = switch (text) {
    _ when text.startsWith('flag:') => '标记「${text.substring(5)}」',
    _ when text.startsWith('clue:') => '线索「${text.substring(5)}」',
    _ when text.startsWith('clock_zero:') => '时钟「${text.substring(11)}」归零',
    _ => text,
  };
  return negate ? '未获得$label' : '已获得$label';
}
