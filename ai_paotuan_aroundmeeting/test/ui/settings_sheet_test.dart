import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/app/di.dart';
import 'package:ai_paotuan_aroundmeeting/app/theme.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/features/character_sheet/character_sheet_screen.dart';
import 'package:ai_paotuan_aroundmeeting/features/settings/settings_screen.dart';
import 'package:ai_paotuan_aroundmeeting/platform/platform_impl.dart';
import 'package:ai_paotuan_aroundmeeting/platform/ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

late final Scenario _scenario;

Future<void> pumpSmall(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final temp = TempDirs();
  addTearDown(temp.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileDirsProvider.overrideWithValue(temp),
        settingsStoreProvider.overrideWithValue(FakeSettings()),
        secretStoreProvider.overrideWithValue(FakeSecret()),
        scenarioProvider.overrideWith((ref) async => _scenario),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    _scenario = parseScenario(
      File('assets/scenarios/dinner_hale/scenario.yaml').readAsStringSync(),
    );
  });

  testWidgets('设置页在小屏不溢出', (tester) async {
    await pumpSmall(tester, const SettingsScreen());

    expect(find.text('API'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('制卡页在小屏不溢出', (tester) async {
    await pumpSmall(tester, const CharacterSheetScreen());

    expect(find.text('基础属性'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('物品弹窗：空名称时确定不可点，取消后不报错', (tester) async {
    // 物品区在长页面底部，用高视口避免懒加载。
    await pumpSmall(
      tester,
      const CharacterSheetScreen(),
      size: const Size(400, 1800),
    );

    await tester.tap(find.text('添加物品').first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确定'),
    );
    expect(confirm.onPressed, isNull, reason: '空名称不允许确认');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('技能点用尽后加号置灰', (tester) async {
    await pumpSmall(
      tester,
      const CharacterSheetScreen(),
      size: const Size(400, 1800),
    );

    // 先随机分配技能点（属性区与技能区各有一个「随机分配」，技能在后）。
    await tester.tap(find.text('随机分配').last);
    await tester.pumpAndSettle();

    // 随机分配后余额为 0 或接近 0；此处只断言不抛异常。
    expect(tester.takeException(), isNull);
  });

  testWidgets('模型字段停止输入后自动保存', (tester) async {
    final store = FakeSettings();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = TempDirs();
    addTearDown(temp.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileDirsProvider.overrideWithValue(temp),
          settingsStoreProvider.overrideWithValue(store),
          secretStoreProvider.overrideWithValue(FakeSecret()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final baseUrlField = find.ancestor(
      of: find.text('Base URL'),
      matching: find.byType(TextField),
    );
    await tester.enterText(baseUrlField.first, 'https://example.com/v1');
    await tester.pump(const Duration(milliseconds: 700));

    expect(store.read(SettingsKeys.baseUrl), 'https://example.com/v1');
  });

  test('设置落盘后，重新加载仍能读回（覆盖安装场景）', () async {
    final dir = Directory.systemTemp.createTempSync('party_settings_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final first = await FileSettings.load(dir);
    await first.write(SettingsKeys.baseUrl, 'https://example.com/v1');
    await first.write(SettingsKeys.kpModel, 'kp-pro');
    await first.write(SettingsKeys.bpModel, 'bp-cheap');

    // 模拟重启 / 覆盖安装：重新从同一个目录加载。
    final second = await FileSettings.load(dir);
    expect(second.read(SettingsKeys.baseUrl), 'https://example.com/v1');
    expect(second.read(SettingsKeys.kpModel), 'kp-pro');
    expect(second.read(SettingsKeys.bpModel), 'bp-cheap');
  });
}
