import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/di.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'data/archive/archiver.dart';
import 'data/archive/file_archive_repository.dart';
import 'data/storage/file_event_store.dart';
import 'platform/platform_impl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 竖屏（PRD 05 §1）：失败也不能挡住启动。
  unawaited(_lockPortrait());

  const dirs = PathProviderDirs();
  final dataDir = await _resolveDataDir(dirs);

  // 设置与密钥都落在应用私有目录，覆盖安装后仍能读回。
  final settings = await FileSettings.load(dataDir);
  SecureStorageSecret.dataDir = dataDir;

  runApp(
    ProviderScope(
      overrides: [
        fileDirsProvider.overrideWithValue(dirs),
        settingsStoreProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(const SecureStorageSecret()),
        eventStoreProvider.overrideWithValue(FileEventStore(dataDir)),
        archiveRepositoryProvider.overrideWithValue(
          FileArchiveRepository(Archiver(dataDir)),
        ),
      ],
      child: const PartyApp(),
    ),
  );
}

Future<Directory> _resolveDataDir(PathProviderDirs dirs) async {
  try {
    return await dirs.appData();
  } catch (error) {
    return Directory('${Directory.systemTemp.path}/party_of_ais');
  }
}

Future<void> _lockPortrait() async {
  try {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  } catch (error) {
    debugPrint('BOOT: orientation failed: $error');
  }
}

class PartyApp extends StatefulWidget {
  const PartyApp({super.key});

  @override
  State<PartyApp> createState() => _PartyAppState();
}

class _PartyAppState extends State<PartyApp> {
  @override
  void initState() {
    super.initState();
    // 启动即主页：不接深链、不恢复上次页面。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = appRouter.routerDelegate.currentConfiguration.uri;
      if (location.toString() != '/') {
        appRouter.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '一人成团',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
      builder: (context, child) => ColoredBox(
        color: AppColors.background,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
