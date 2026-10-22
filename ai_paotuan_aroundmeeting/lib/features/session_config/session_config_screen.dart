import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../engine/scenario/bp_names.dart';
import '../../engine/scenario/scenario.dart';

/// 对局设置：AI 玩家数量与名字（PRD 05 §2.4 / 你的要求）。
class SessionConfigScreen extends ConsumerStatefulWidget {
  const SessionConfigScreen({super.key});

  @override
  ConsumerState<SessionConfigScreen> createState() =>
      _SessionConfigScreenState();
}

class _SessionConfigScreenState extends ConsumerState<SessionConfigScreen> {
  int _bpCount = 1;
  List<String> _names = <String>[];
  bool _initialized = false;

  Scenario? _scenario;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _scenario = ref.read(scenarioProvider).valueOrNull;
    _bpCount = ref.read(sessionConfigProvider).bpCount;
    _names = List<String>.from(ref.read(sessionConfigProvider).bpNames);
    _initialized = true;
  }

  int get _maxBp {
    final scenario = _scenario;
    if (scenario == null) return 1;
    final maxByPool = scenario.bpActors.length;
    final maxByParty = scenario.partyMax - 1 - scenario.npcs.length;
    final value = maxByPool < maxByParty ? maxByPool : maxByParty;
    return value < 1 ? 1 : value;
  }

  void _ensureNames(String playerName) {
    if (_names.length >= _bpCount) return;
    _names = <String>[
      ..._names,
      ...pickBpNames(_bpCount - _names.length, playerName: playerName),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // watch 而不是只读一次：直接深链进来时也能等剧本加载完再渲染。
    final scenario = ref.watch(scenarioProvider).valueOrNull ?? _scenario;
    final character = ref.watch(characterProvider);

    if (scenario == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _ensureNames(character.name);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/scenarios'),
        ),
        title: const Text(
          '对 局 设 置',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(scenario.title, style: sectionLabel()),
          const SizedBox(height: 8),
          Text(
            '你：${character.name.isEmpty ? '无名' : character.name}'
            ' · 剧本 ${scenario.title}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Text('AI 玩家数量', style: TextStyle(fontSize: 14)),
              const Spacer(),
              IconButton(
                onPressed: _bpCount > 1
                    ? () => setState(() => _bpCount -= 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_bpCount', style: const TextStyle(fontSize: 18)),
              IconButton(
                onPressed: _bpCount < _maxBp
                    ? () => setState(() => _bpCount += 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          Text(
            '本剧本 2–${scenario.partyMax} 人局，AI 玩家最多 $_maxBp 个。',
            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < _bpCount; index++) ...[
            TextFormField(
              key: ValueKey<String>('bp-name-$index-${_names[index]}'),
              initialValue: _names[index],
              maxLength: 12,
              decoration: InputDecoration(
                labelText: 'AI 玩家 ${index + 1} 的名字',
                counterText: '',
              ),
              onChanged: (value) {
                _names[index] = value.trim();
              },
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _names = pickBpNames(_bpCount, playerName: character.name);
              });
            },
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: const Text('随机换一批名字'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              _ensureNames(character.name);
              final config = SessionConfig(
                bpCount: _bpCount,
                bpNames: List<String>.from(_names.take(_bpCount)),
              );
              ref.read(sessionConfigProvider.notifier).apply(config);
              context.go('/table');
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brass,
              foregroundColor: AppColors.parchmentInk,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('开始上桌'),
          ),
        ],
      ),
    );
  }
}
