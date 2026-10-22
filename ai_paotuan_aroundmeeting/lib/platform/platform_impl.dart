import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'ports.dart';

/// 兜底目录：OHOS 上 path_provider 没有实现，先用应用沙箱临时目录。
///
/// TODO(ohos): 用 ArkTS MethodChannel 暴露 `context.filesDir` 后替换这里。
Directory _fallbackDir() =>
    Directory('${Directory.systemTemp.path}/party_of_ais');

/// `path_provider` 实现；不可用时退到沙箱临时目录。
class PathProviderDirs implements FileDirsPort {
  const PathProviderDirs();

  Future<Directory> _ensure(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<Directory> appData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return _ensure(dir);
    } catch (error) {
      return _ensure(_fallbackDir());
    }
  }

  @override
  Future<Directory> cache() async {
    try {
      return await getTemporaryDirectory();
    } catch (error) {
      return _ensure(_fallbackDir());
    }
  }
}

/// 设置落盘：`{dataDir}/settings.json`。
///
/// 不用 shared_preferences（OHOS 没有实现）；覆盖安装后仍能读回。
class FileSettings implements SettingsPort {
  FileSettings._(this._values, this._file);

  static Future<FileSettings> load(Directory dataDir) async {
    await dataDir.create(recursive: true);
    final file = File('${dataDir.path}/settings.json');
    final values = <String, String>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((key, value) {
            values[key.toString()] = value.toString();
          });
        }
      }
    } catch (error) {
      debugPrint('读取设置失败，使用默认值：$error');
    }
    return FileSettings._(values, file);
  }

  final Map<String, String> _values;
  final File _file;

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(_values), flush: true);
    } catch (error) {
      debugPrint('保存设置失败：$error');
    }
  }
}

/// 密钥存储：优先系统安全存储；平台不支持时退到应用目录文件（明文，仅本机）。
///
/// OHOS 没有 flutter_secure_storage 实现，第一次失败后就把能力置为不可用，
/// 之后直接走文件兜底——只提示一次，不刷屏。
class SecureStorageSecret implements SecretPort {
  const SecureStorageSecret();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 已确认当前平台没有安全存储实现。
  static bool _secureUnavailable = false;

  /// 兜底文件所在目录，由 main 在启动时注入（应用私有目录）。
  static Directory? dataDir;

  File get _fallbackFile =>
      File('${(dataDir ?? _fallbackDir()).path}/secrets.json');

  Future<Map<String, String>> _readFallback() async {
    try {
      if (!await _fallbackFile.exists()) return <String, String>{};
      final decoded = jsonDecode(await _fallbackFile.readAsString());
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeFallback(Map<String, String> data) async {
    try {
      await _fallbackFile.parent.create(recursive: true);
      await _fallbackFile.writeAsString(jsonEncode(data), flush: true);
    } catch (error) {
      debugPrint('密钥兜底写入失败：$error');
    }
  }

  /// 平台不支持（OHOS）是预期情况，静默降级；其它错误才值得打印。
  void _handleError(String action, Object error) {
    if (_markUnavailableIfUnsupported(error)) return;
    debugPrint('安全存储不可用（$action），走兜底：$error');
  }

  bool _markUnavailableIfUnsupported(Object error) {
    final unsupported =
        error is UnsupportedError ||
        error.toString().contains('unsupported_platform');
    if (!unsupported) return false;

    _secureUnavailable = true;
    return true;
  }

  @override
  Future<String?> read(String key) async {
    if (!_secureUnavailable) {
      try {
        final value = await _storage.read(key: key);
        if (value != null && value.isNotEmpty) return value;
      } catch (error) {
        _handleError('读', error);
      }
    }
    final data = await _readFallback();
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_secureUnavailable) {
      try {
        await _storage.write(key: key, value: value);
        // 有些平台会「静默成功」但没存，读回校验一次。
        final check = await _storage.read(key: key);
        if (check == value) return;
      } catch (error) {
        _handleError('写', error);
      }
    }
    final data = await _readFallback();
    data[key] = value;
    await _writeFallback(data);
  }

  @override
  Future<void> delete(String key) async {
    if (!_secureUnavailable) {
      try {
        await _storage.delete(key: key);
      } catch (error) {
        _handleError('删', error);
      }
    }
    final data = await _readFallback();
    data.remove(key);
    await _writeFallback(data);
  }
}
