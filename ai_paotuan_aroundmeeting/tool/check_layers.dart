import 'dart:io';

/// 轻量分层检查：不引入额外 lint 插件，CI 里直接 `dart run tool/check_layers.dart`。
void main() {
  final rules = <String, List<RegExp>>{
    'lib/engine/': <RegExp>[
      RegExp(r"package:flutter/"),
      RegExp(r"import 'dart:io'"),
      RegExp(r"package:yaml/"),
      RegExp(r"package:dio/"),
    ],
    'lib/application/': <RegExp>[
      RegExp(r"package:flutter/"),
      RegExp(r"import 'dart:io'"),
      RegExp(r"package:yaml/"),
      RegExp(r"package:dio/"),
    ],
    'lib/features/': <RegExp>[
      RegExp(r"import 'dart:io'"),
      RegExp(r"package:yaml/"),
      RegExp(r"package:dio/"),
      RegExp(r"import '.*/(data|llm|platform)/"),
    ],
  };

  final violations = <String>[];
  for (final entry in rules.entries) {
    final dir = Directory(entry.key);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final rule in entry.value) {
        if (rule.hasMatch(text)) {
          violations.add('${file.path}: 命中禁止依赖 ${rule.pattern}');
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('layer check: ok');
    return;
  }
  for (final violation in violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}
