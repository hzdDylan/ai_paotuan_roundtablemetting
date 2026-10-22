import 'package:go_router/go_router.dart';

import '../features/character_sheet/character_sheet_screen.dart';
import '../features/home/home_screen.dart';
import '../features/how_to_play/how_to_play_screen.dart';
import '../features/journal/journal_screen.dart';
import '../features/scenario_select/scenario_select_screen.dart';
import '../features/session_config/session_config_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/table/table_screen.dart';
import '../ui/widgets/back_scope.dart';

/// 路由表（D-10 = A：go_router，纯 Dart、无平台插件）。
///
/// 除首页外都包一层 [BackScope]：系统返回键 / 侧滑回上一级，而不是退出应用。
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  // 任何匹配不上的路径（网页子路径、旧深链、手滑）都回主页，而不是错误页。
  errorBuilder: (context, state) => const HomeScreen(),
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/scenarios',
      builder: (context, state) =>
          const BackScope(child: ScenarioSelectScreen()),
    ),
    GoRoute(
      path: '/session-config',
      builder: (context, state) =>
          const BackScope(child: SessionConfigScreen()),
    ),
    GoRoute(
      path: '/sheet',
      builder: (context, state) =>
          const BackScope(child: CharacterSheetScreen()),
    ),
    GoRoute(
      path: '/table',
      builder: (context, state) => const BackScope(child: TableScreen()),
    ),
    GoRoute(
      path: '/journal',
      builder: (context, state) => const BackScope(child: JournalScreen()),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const BackScope(child: SettingsScreen()),
    ),
    GoRoute(
      path: '/how-to-play',
      builder: (context, state) => const BackScope(child: HowToPlayScreen()),
    ),
  ],
);
