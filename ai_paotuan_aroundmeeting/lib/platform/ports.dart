import 'dart:io';

/// 平台端口（SE §7.2）。领域层只认这些接口。
abstract interface class FileDirsPort {
  Future<Directory> appData();
  Future<Directory> cache();
}

abstract interface class SettingsPort {
  String? read(String key);
  Future<void> write(String key, String value);
}

abstract interface class SecretPort {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
