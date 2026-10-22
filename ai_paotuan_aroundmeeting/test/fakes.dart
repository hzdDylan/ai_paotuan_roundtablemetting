import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/platform/ports.dart';

/// 测试用：内存版密钥仓。
class FakeSecret implements SecretPort {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// 测试用：内存版设置。
class FakeSettings implements SettingsPort {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// 测试用：临时目录（调用方负责删除）。
class TempDirs implements FileDirsPort {
  TempDirs() : _root = Directory.systemTemp.createTempSync('party_of_ais_test');

  final Directory _root;

  Directory get root => _root;

  @override
  Future<Directory> appData() async => _root;

  @override
  Future<Directory> cache() async => _root;

  void dispose() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  }
}
