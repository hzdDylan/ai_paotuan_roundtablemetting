import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/engine/moderation/moderation.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_lint.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scene_flow.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _paths = <String>[
  'assets/scenarios/dinner_hale/scenario.yaml',
  'assets/scenarios/mist_dock/scenario.yaml',
  'assets/scenarios/paramount_last_dance/scenario.yaml',
  'assets/scenarios/xiafei_47/scenario.yaml',
];

void main() {
  late List<Scenario> scenarios;

  setUpAll(() {
    scenarios = [
      for (final path in _paths) parseScenario(File(path).readAsStringSync()),
    ];
  });

  test('四个内置剧本都能解析', () {
    expect(scenarios, hasLength(4));
    expect(
      scenarios.map((scenario) => scenario.id),
      containsAll(<String>[
        'dinner_hale',
        'mist_dock',
        'paramount_last_dance',
        'xiafei_47',
      ]),
    );
  });

  test('每个剧本都有完整场景图与终幕', () {
    for (final scenario in scenarios) {
      expect(
        scenario.scenes.length,
        greaterThanOrEqualTo(7),
        reason: '${scenario.id} 的场景太少',
      );
      expect(
        scenario.scenes.where((scene) => scene.ending),
        isNotEmpty,
        reason: '${scenario.id} 没有 ending 场景',
      );

      final ids = scenario.scenes.map((scene) => scene.id).toSet();
      for (final scene in scenario.scenes) {
        if (scene.ending) continue;
        expect(
          scene.exits,
          isNotEmpty,
          reason: '${scenario.id}/${scene.id} 没有出口',
        );
        for (final exit in scene.exits) {
          expect(
            ids,
            contains(exit.to),
            reason: '${scenario.id}/${scene.id} 的出口指向 ${exit.to}',
          );
        }
        // 每条非终幕都至少有一条无条件出口，避免被单次检定锁死。
        expect(
          scene.exits.any(
            (exit) => exit.when.trim().isEmpty || exit.when.trim() == 'always',
          ),
          isTrue,
          reason: '${scenario.id}/${scene.id} 没有保底出口',
        );
      }
    }
  });

  test('每个场景都能从首幕走到', () {
    for (final scenario in scenarios) {
      final byId = <String, SceneDef>{
        for (final scene in scenario.scenes) scene.id: scene,
      };
      final reached = <String>{scenario.scenes.first.id};
      final queue = <String>[scenario.scenes.first.id];
      while (queue.isNotEmpty) {
        final current = byId[queue.removeAt(0)]!;
        for (final exit in current.exits) {
          if (reached.add(exit.to)) queue.add(exit.to);
        }
      }
      expect(
        reached,
        containsAll(byId.keys),
        reason:
            '${scenario.id} 有走不到的场景：${byId.keys.toSet().difference(reached)}',
      );
    }
  });

  test('固定开场白不直接写出未揭示线索', () {
    for (final scenario in scenarios) {
      for (final scene in scenario.scenes) {
        for (final clue in scene.clues) {
          expect(
            scenario.opening.contains(clue.text),
            isFalse,
            reason: '${scenario.id} 开场白泄露了线索 ${clue.id}',
          );
        }
      }
    }
  });

  test('固定开场白只写 KP 背景，不出现玩家或 BP 动作', () {
    final playerAction = RegExp(r'你(推|走|说|问|拿|数|攥|站|坐|抬|看|拉|举|敲|翻|掏|递|受|把|将)');
    for (final scenario in scenarios) {
      expect(
        scenario.opening,
        isNot(contains('「')),
        reason: '${scenario.id} 开场白出现了台词',
      );
      expect(
        scenario.opening,
        isNot(contains('“')),
        reason: '${scenario.id} 开场白出现了台词',
      );
      expect(
        playerAction.hasMatch(scenario.opening),
        isFalse,
        reason: '${scenario.id} 开场白出现了玩家动作',
      );
      for (final bp in scenario.bpActors) {
        expect(
          scenario.opening.contains(bp.name),
          isFalse,
          reason: '${scenario.id} 开场白让 BP「${bp.name}」提前出场行动',
        );
      }
    }
  });

  test('每个剧本只有 1–2 个致命检定，且都指向终幕', () {
    for (final scenario in scenarios) {
      final fatal = <SceneCheck>[];
      for (final scene in scenario.scenes) {
        for (final check in scene.checks) {
          if (check.onFumble == null) continue;
          fatal.add(check);
          final target = scenario.sceneById(check.onFumble!.ending);
          expect(
            target,
            isNotNull,
            reason: '${scenario.id}/${scene.id} 的致命检定指向不存在的终幕',
          );
          expect(
            target!.ending,
            isTrue,
            reason: '${scenario.id}/${scene.id} 的致命检定必须进入 ending 场景',
          );
          expect(
            check.onFumble!.text.trim(),
            isNotEmpty,
            reason: '${scenario.id}/${scene.id} 的致命检定没有收场提示',
          );
        }
      }
      expect(
        fatal.length,
        inInclusiveRange(1, 2),
        reason: '${scenario.id} 的致命检定数量应为 1–2',
      );
    }
  });

  test('同一剧本内线索 id 全局唯一', () {
    for (final scenario in scenarios) {
      final seen = <String>{};
      for (final scene in scenario.scenes) {
        for (final clue in scene.clues) {
          expect(
            seen.add(clue.id),
            isTrue,
            reason: '${scenario.id} 线索 id 重复：${clue.id}',
          );
        }
      }
    }
  });

  test('每个 BP 都有目标、秘密、吐槽与善变诱因', () {
    for (final scenario in scenarios) {
      for (final bp in scenario.bpActors) {
        expect(bp.goal, isNotEmpty, reason: '${scenario.id}/${bp.id}');
        expect(bp.secret, isNotEmpty, reason: '${scenario.id}/${bp.id}');
        expect(bp.quip, isNotEmpty, reason: '${scenario.id}/${bp.id}');
        expect(bp.switchTrigger, isNotEmpty, reason: '${scenario.id}/${bp.id}');
        expect(bp.tags, isNotEmpty, reason: '${scenario.id}/${bp.id}');
      }
    }
  });

  test('首幕检定从普通难度开始，且每项都有失败代价', () {
    for (final scenario in scenarios) {
      final first = scenario.scenes.first;
      expect(first.checks, isNotEmpty, reason: '${scenario.id} 首幕没有检定');
      expect(
        first.checks.first.difficulty,
        Difficulty.regular,
        reason: '${scenario.id} 首幕第一项不是 regular',
      );
      for (final scene in scenario.scenes) {
        for (final check in scene.checks) {
          expect(
            check.stakes.trim(),
            isNotEmpty,
            reason: '${scenario.id}/${scene.id} 的 ${check.label} 没有代价',
          );
        }
      }
    }
  });

  test('lint 无 error', () {
    for (final scenario in scenarios) {
      final report = lintScenario(scenario);
      expect(report.errors, isEmpty, reason: report.toReadable());
    }
  });

  test('lint 无 warning', () {
    for (final scenario in scenarios) {
      final report = lintScenario(scenario);
      expect(report.warnings, isEmpty, reason: report.toReadable());
    }
  });

  test('出口条件由 flag / clue / 时钟打开', () {
    final scenario = scenarios.firstWhere(
      (scenario) => scenario.id == 'dinner_hale',
    );
    final porch = scenario.sceneById('porch')!;
    final invited = porch.exits.firstWhere((exit) => exit.id == 'invited');
    expect(
      isExitOpen(
        invited,
        flags: const <String>{},
        clues: const <String>{},
        clocks: const <String, int>{},
      ),
      isFalse,
    );
    expect(
      isExitOpen(
        invited,
        flags: const <String>{'gu_accepted_invite'},
        clues: const <String>{},
        clocks: const <String, int>{},
      ),
      isTrue,
    );

    final refused = porch.exits.firstWhere((exit) => exit.id == 'refused');
    expect(
      isExitOpen(
        refused,
        flags: const <String>{},
        clues: const <String>{},
        clocks: const <String, int>{'gu_patience': 0},
      ),
      isTrue,
    );
  });

  test('解析核心字段', () {
    final scenario = scenarios.first;
    expect(scenario.id, 'dinner_hale');
    expect(scenario.title, contains('顾先生'));
    expect(scenario.actors, hasLength(3));
    expect(scenario.npcs, hasLength(1));
    expect(scenario.scenes.first.id, 'porch');
  });

  test('桌上人数 = 4（不含 KP，Q-01）', () {
    expect(scenarios.first.partySize, 4);
  });

  test('检定只写技能 / 难度 / 代价，不写目标值（D-05）', () {
    final checks = scenarios.first.sceneById('porch')!.checks;
    expect(
      checks.map((check) => check.skill),
      containsAll(<Skill>[Skill.persuade, Skill.psychology, Skill.spotHidden]),
    );
    expect(checks.first.difficulty, Difficulty.regular);
    expect(checks.first.stakes, isNotEmpty);
  });

  test('content_scope 可用于审核', () {
    expect(scenarios.first.contentScope.era, contains('1935'));
    expect(scenarios.first.contentScope.toPromptBlock(), contains('1935'));
  });

  test('lint 能抓出「没有出口」的场景', () {
    final broken = Scenario(
      id: 'broken',
      version: '0.0.1',
      title: '坏剧本',
      contentScope: const ContentScope(),
      actors: scenarios.first.actors,
      npcs: scenarios.first.npcs,
      scenes: const [SceneDef(id: 's1', name: '空场景', goal: '无')],
    );
    final report = lintScenario(broken);
    expect(report.errors.any((error) => error.contains('没有出口')), isTrue);
  });
}
