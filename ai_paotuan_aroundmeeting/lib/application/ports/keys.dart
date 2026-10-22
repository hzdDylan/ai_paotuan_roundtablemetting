/// 设置与密钥键名集中在这里，避免 UI / 存储层散落魔法字符串。
abstract final class SettingsKeys {
  static const baseUrl = 'base_url';
  static const kpModel = 'kp_model';
  static const bpModel = 'bp_model';
  static const presentation = 'presentation'; // instant | fade
  static const motion = 'motion'; // on | off
}

abstract final class SecretKeys {
  static const apiKey = 'api_key';
}
