import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/app/di.dart';
import 'package:ai_paotuan_aroundmeeting/app/router.dart';
import 'package:ai_paotuan_aroundmeeting/app/theme.dart';
import 'package:ai_paotuan_aroundmeeting/engine/archive/archiver.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/features/journal/journal_screen.dart';
import 'package:ai_paotuan_aroundmeeting/features/table/table_screen.dart';
import 'package:ai_paotuan_aroundmeeting/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

late final Scenario _scenario;
late final List<Scenario> _catalog;

List<Override> _baseOverrides(TempDirs temp) => <Override>[
  fileDirsProvider.overrideWithValue(temp),
  settingsStoreProvider.overrideWithValue(FakeSettings()),
  secretStoreProvider.overrideWithValue(FakeSecret()),
  scenarioProvider.overrideWith((ref) async => _scenario),
  scenarioCatalogProvider.overrideWith((ref) async => _catalog),
];

void _sizeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpPartyApp(WidgetTester tester) async {
  _sizeViewport(tester);
  final temp = TempDirs();
  addTearDown(temp.dispose);

  await tester.pumpWidget(
    ProviderScope(overrides: _baseOverrides(temp), child: const PartyApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> extraOverrides = const <Override>[],
}) async {
  _sizeViewport(tester);
  final temp = TempDirs();
  addTearDown(temp.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [..._baseOverrides(temp), ...extraOverrides],
      child: MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() {
    const paths = <String>[
      'assets/scenarios/dinner_hale/scenario.yaml',
      'assets/scenarios/mist_dock/scenario.yaml',
      'assets/scenarios/paramount_last_dance/scenario.yaml',
      'assets/scenarios/xiafei_47/scenario.yaml',
    ];
    _catalog = [
      for (final path in paths) parseScenario(File(path).readAsStringSync()),
    ];
    _scenario = _catalog.first;
  });

  test('切换选中的剧本会重新加载对应剧本', () async {
    final container = ProviderContainer(
      overrides: [
        scenarioCatalogProvider.overrideWith((ref) async => _catalog),
      ],
    );
    addTearDown(container.dispose);

    expect((await container.read(scenarioProvider.future)).id, 'dinner_hale');
    container.read(selectedScenarioIdProvider.notifier).select('mist_dock');
    expect((await container.read(scenarioProvider.future)).id, 'mist_dock');
  });

  testWidgets('首页渲染五个入口与状态条', (tester) async {
    await pumpPartyApp(tester);

    expect(find.text('一 人 成 团'), findsOneWidget);
    for (final label in ['选择剧本', '游戏说明', '记忆回廊', '制卡', '设置']) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }
    expect(find.text('未配置 API'), findsOneWidget);
  });

  testWidgets('冷启动总是回主页（即使上次停在别处）', (tester) async {
    appRouter.go('/settings');
    await tester.pump();

    await pumpPartyApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('一 人 成 团'), findsOneWidget);
    expect(find.text('设 置'), findsNothing);
  });

  testWidgets('从首页进制卡，能看到属性', (tester) async {
    await pumpPartyApp(tester);

    await tester.tap(find.text('制卡'));
    await tester.pumpAndSettle();

    expect(find.text('制 卡'), findsOneWidget);
    expect(find.text('基础属性'), findsOneWidget);
    expect(find.text('力量'), findsOneWidget);
    expect(find.text('技能'), findsOneWidget);
  });

  testWidgets('从首页进选择剧本', (tester) async {
    await pumpPartyApp(tester);

    await tester.tap(find.text('选择剧本'));
    await tester.pumpAndSettle();

    expect(find.text('选 择 剧 本'), findsOneWidget);
    expect(find.text('顾先生的晚宴'), findsOneWidget);
    expect(find.text('雾码头'), findsOneWidget);
    expect(find.text('百乐门最后一支舞'), findsOneWidget);
    expect(find.text('霞飞路 47 号'), findsOneWidget);
    expect(find.text('自定义剧本'), findsOneWidget);
  });

  testWidgets('没有 key 时上桌会提示去设置', (tester) async {
    await pumpScreen(tester, const TableScreen());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('还没有 API key'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('记忆回廊空状态', (tester) async {
    await pumpScreen(
      tester,
      const JournalScreen(),
      extraOverrides: [
        archiveListProvider.overrideWith((ref) async => <ArchiveRecord>[]),
      ],
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('还没有归档。跑一局，回来看看。'), findsOneWidget);
  });
}
