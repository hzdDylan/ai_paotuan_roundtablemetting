import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../llm/llm_client.dart';
import '../../platform/ports.dart';

enum _TestState { idle, testing, ok, failed }

/// 设置（PRD 05 §6 / SE §4.8）：固定布局，不滚动。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _loading = true;
  bool _reveal = false;
  _TestState _testState = _TestState.idle;
  String _testMessage = '';

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final secret = ref.read(secretStoreProvider);
    final key = await secret.read(SecretKeys.apiKey);
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _loading = false;
    });
  }

  Future<void> _saveKey() async {
    final secret = ref.read(secretStoreProvider);
    final value = _keyController.text.trim();
    if (value.isEmpty) {
      await secret.delete(SecretKeys.apiKey);
    } else {
      await secret.write(SecretKeys.apiKey, value);
    }
    // 关键：首页的 key 状态是 FutureProvider，必须失效才会重新读。
    ref.invalidate(apiKeyProvider);
    setState(() => _testState = _TestState.idle);
    if (!mounted) return;
    _toast(value.isEmpty ? '已清除 API key' : '已保存到本机');
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testState = _TestState.failed;
        _testMessage = '先填 key';
      });
      return;
    }

    setState(() {
      _testState = _TestState.testing;
      _testMessage = '连接中…';
    });

    final settings = ref.read(settingsProvider);
    final client = LlmClient(baseUrl: settings.baseUrl, apiKey: key);
    try {
      await client.ping(model: settings.kpModel);
      if (!mounted) return;
      setState(() {
        _testState = _TestState.ok;
        _testMessage = '连通正常';
      });
    } on LlmException catch (error) {
      if (!mounted) return;
      setState(() {
        _testState = _TestState.failed;
        _testMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testState = _TestState.failed;
        _testMessage = '$error';
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          '设 置',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
        actions: [
          IconButton(
            tooltip: '测试连通',
            onPressed: _testState == _TestState.testing
                ? null
                : _testConnection,
            icon: const Icon(Icons.wifi_tethering, size: 18),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          // 按需求不滚动：内容超出时整体等比缩小，小屏也不会溢出。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionHeader('API'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _keyController,
                    obscureText: !_reveal,
                    decoration: InputDecoration(
                      labelText: 'API key',
                      hintText: _loading ? '读取中…' : 'sk-…',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _reveal ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _reveal = !_reveal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brass,
                            foregroundColor: AppColors.parchmentInk,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('保存 key'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _keyController.clear();
                            _saveKey();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink,
                            side: const BorderSide(color: Color(0x66C9A227)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('清除'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'key 保存在本机安全存储中，不会上传。',
                    style: TextStyle(fontSize: 10, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const _SectionHeader('模型'),
                      const Spacer(),
                      _TestButton(
                        state: _testState,
                        message: _testMessage,
                        onTap: _testConnection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _ModelField(
                    label: 'Base URL',
                    value: settings.baseUrl,
                    onSubmitted: settingsNotifier.setBaseUrl,
                  ),
                  const SizedBox(height: 8),
                  _ModelField(
                    label: 'KP 模型',
                    value: settings.kpModel,
                    onSubmitted: settingsNotifier.setKpModel,
                  ),
                  const SizedBox(height: 8),
                  _ModelField(
                    label: 'BP 模型',
                    value: settings.bpModel,
                    onSubmitted: settingsNotifier.setBpModel,
                  ),
                  const SizedBox(height: 16),
                  const _SectionHeader('呈现'),
                  // 不用 ListTile/Switch 自带的水波纹：长按会出现按压填充。
                  _ToggleRow(
                    label: '段落淡入',
                    value: settings.fadeSegments,
                    onChanged: settingsNotifier.setFadeSegments,
                  ),
                  _ToggleRow(
                    label: '动效',
                    value: settings.motion,
                    onChanged: settingsNotifier.setMotion,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '一人成团（We Saved You a Seat）\nv0.1.0 · 个人项目\n代码 MIT；剧本 CC-BY-NC 4.0',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 开关行：普通 Row + 无 overlay 的 Switch，避免长按出现按压填充动画。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            overlayColor: const WidgetStatePropertyAll<Color?>(
              Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 连通测试按钮：圆点颜色 + 文案，点一下就跑一次。
class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.state,
    required this.message,
    required this.onTap,
  });

  final _TestState state;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _TestState.idle => const Color(0x88FFFFFF),
      _TestState.testing => AppColors.brass,
      _TestState.ok => const Color(0xFF4CAF50),
      _TestState.failed => const Color(0xFFE53935),
    };
    final label = switch (state) {
      _TestState.idle => '测试',
      _TestState.testing => '…',
      _TestState.ok => '连通',
      _TestState.failed => '失败',
    };

    return Tooltip(
      message: message.isEmpty ? '测试 API 连通性' : message,
      child: OutlinedButton(
        onPressed: state == _TestState.testing ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          side: BorderSide(color: color.withValues(alpha: 0.7)),
          minimumSize: const Size(0, 40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// 模型输入框：停止输入 600ms 自动保存（不用回车）。
class _ModelField extends StatefulWidget {
  const _ModelField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_ModelField> createState() => _ModelFieldState();
}

class _ModelFieldState extends State<_ModelField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final value = text.trim();
      if (value.isNotEmpty && value != widget.value) {
        widget.onSubmitted(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: _onChanged,
      textInputAction: TextInputAction.done,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: sectionLabel());
  }
}
