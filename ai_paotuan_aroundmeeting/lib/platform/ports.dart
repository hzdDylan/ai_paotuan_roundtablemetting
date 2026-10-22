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

/// 设置键名集中在这里，避免各处魔法字符串。
abstract final class SettingsKeys {
  static const baseUrl = 'base_url';
  static const kpModel = 'kp_model';
  static const bpModel = 'bp_model';
  static const presentation = 'presentation'; // instant | fade
  static const motion = 'motion'; // on | off
}

/// 密钥键名。
abstract final class SecretKeys {
  static const apiKey = 'api_key';
}
