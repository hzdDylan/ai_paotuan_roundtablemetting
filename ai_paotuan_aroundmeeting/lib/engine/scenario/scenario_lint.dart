import '../rules/check.dart';
import 'scenario.dart';

/// 剧本校验结果（SE §4.12）。
class LintReport {
  const LintReport({
    this.errors = const <String>[],
    this.warnings = const <String>[],
  });

  final List<String> errors;
  final List<String> warnings;

  bool get ok => errors.isEmpty;

  String toReadable() => [
    ...errors.map((e) => '[error] $e'),
    ...warnings.map((w) => '[warn]  $w'),
  ].join('\n');
}

/// 剧本 lint：CI 与打包前都要跑。
LintReport lintScenario(Scenario scenario) {
  final errors = <String>[];
  final warnings = <String>[];

  if (scenario.id.trim().isEmpty) errors.add('剧本 id 不能为空');
  if (scenario.title.trim().isEmpty) errors.add('剧本 title 不能为空');
  if (scenario.scenes.isEmpty) errors.add('至少需要一个场景');
  if (scenario.human == null) errors.add('至少需要一个 human 角色');
  if (scenario.contentScope.isEmpty) {
    errors.add('content_scope 不能为空（审核需要它作为判据）');
  }

  final actorIds = <String>{};
  for (final actor in scenario.actors) {
    if (!actorIds.add(actor.id)) errors.add('角色 id 重复：${actor.id}');
  }
  final npcIds = <String>{};
  for (final npc in scenario.npcs) {
    if (!npcIds.add(npc.id)) errors.add('NPC id 重复：${npc.id}');
  }

  final sceneIds = <String>{};
  final allClueIds = <String>{};
  var fumbleCount = 0;
  for (final scene in scenario.scenes) {
    if (!sceneIds.add(scene.id)) errors.add('场景 id 重复：${scene.id}');
    if (scene.goal.trim().isEmpty) warnings.add('场景 ${scene.id} 没有目标');
    if (!scene.ending && scene.exits.isEmpty) {
      errors.add('场景 ${scene.id} 没有出口');
    }
    if (scene.ending && scene.exits.isNotEmpty) {
      warnings.add('终幕 ${scene.id} 不应再设出口');
    }

    var hasOpenExit = false;
    for (final exit in scene.exits) {
      if (exit.when.trim().isEmpty || exit.when.trim() == 'always') {
        hasOpenExit = true;
      }
    }
    if (!scene.ending && !hasOpenExit) {
      warnings.add('场景 ${scene.id} 没有无条件出口，可能被单一检定锁死');
    }

    final clockIds = <String>{};
    for (final clock in scene.clocks) {
      if (!clockIds.add(clock.id)) {
        errors.add('场景 ${scene.id} 时钟 id 重复：${clock.id}');
      }
      if (clock.max <= 0) {
        errors.add('场景 ${scene.id} 时钟 ${clock.id} 的 max 必须 > 0');
      }
      if (clock.max < 3 || clock.max > 5) {
        warnings.add('场景 ${scene.id} 时钟 ${clock.id} 建议 3–5 格');
      }
      if (clock.onZero.isNotEmpty && scenario.sceneById(clock.onZero) == null) {
        warnings.add('场景 ${scene.id} 时钟 ${clock.id} 的 on_zero 指向未定义场景');
      }
    }

    final clueIds = <String>{};
    for (final clue in scene.clues) {
      if (!clueIds.add(clue.id)) {
        errors.add('场景 ${scene.id} 线索 id 重复：${clue.id}');
      }
      if (!allClueIds.add(clue.id)) {
        errors.add('线索 id 跨场景重复：${clue.id}');
      }
      if (clue.text.trim().isEmpty) {
        warnings.add('线索 ${clue.id} 没有文本');
      }
    }

    final exitIds = <String>{};
    for (final exit in scene.exits) {
      if (!exitIds.add(exit.id)) {
        errors.add('场景 ${scene.id} 出口 id 重复：${exit.id}');
      }
      if (exit.to.trim().isEmpty) {
        errors.add('场景 ${scene.id} 出口 ${exit.id} 缺少 to');
      } else if (scenario.sceneById(exit.to) == null) {
        warnings.add('出口 ${exit.id} 指向未定义场景「${exit.to}」（若为后续幕次可忽略）');
      }
    }

    for (final check in scene.checks) {
      if (check.stakes.trim().isEmpty) {
        warnings.add('场景 ${scene.id} 的「${check.label}」检定没写失败代价');
      }
      final fumble = check.onFumble;
      if (fumble == null) continue;
      fumbleCount++;
      if (fumble.ending.trim().isEmpty) {
        errors.add('场景 ${scene.id} 的「${check.label}」on_fumble 缺少 ending');
      } else {
        final target = scenario.sceneById(fumble.ending);
        if (target == null) {
          errors.add(
            '场景 ${scene.id} 的「${check.label}」on_fumble 指向未定义场景「${fumble.ending}」',
          );
        } else if (!target.ending) {
          errors.add(
            '场景 ${scene.id} 的「${check.label}」on_fumble 必须指向 ending 场景',
          );
        }
      }
      if (fumble.text.trim().isEmpty) {
        warnings.add('场景 ${scene.id} 的「${check.label}」on_fumble 没写收场提示');
      }
    }
    final extremes = scene.checks
        .where((check) => check.difficulty == Difficulty.extreme)
        .length;
    if (extremes > 1) {
      warnings.add('场景 ${scene.id} 的极难检定超过 1 个');
    }
    if (scene.ending && (scene.checks.isNotEmpty || scene.clocks.isNotEmpty)) {
      warnings.add('终幕 ${scene.id} 不应再设检定或时钟');
    }
  }

  if (fumbleCount > 2) {
    errors.add('致命检定（on_fumble）最多 2 个，当前 $fumbleCount');
  }

  for (final bp in scenario.bpActors) {
    if (bp.tags.isEmpty) {
      warnings.add('BP ${bp.id} 没有标签，Director 相关性打分会失真');
    }
    if (bp.quip.trim().isEmpty) {
      warnings.add('BP ${bp.id} 没有吐槽示例');
    }
    if (bp.switchTrigger.trim().isEmpty) {
      warnings.add('BP ${bp.id} 没有善变诱因');
    }
  }

  final size = scenario.partySize;
  if (size < 2) errors.add('桌上人数至少 2（Q-01），当前 $size');
  if (size > 6) errors.add('桌上人数最多 6（Q-01），当前 $size');

  return LintReport(errors: errors, warnings: warnings);
}
