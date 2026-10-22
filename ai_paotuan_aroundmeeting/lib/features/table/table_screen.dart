import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../engine/rules/check.dart';
import '../../engine/turn/action_suggestion.dart';
import '../../ui/widgets/parchment_panel.dart';
import '../../ui/widgets/seat_avatar.dart';
import 'table_notifier.dart';
import 'transcript_screen.dart';

/// 跑团页（PRD 05 §4）：固定排版，不滚动。
///
/// 布局优先级：顶部栏 → 底部选项/输入（固定）→ 气泡（可压缩）→ 桌子（按剩余高度缩放）。
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _started = false;

  Roll? _toastRoll;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_started) return;
      _started = true;
      // 已有进行中的对局就直接续上，不再重新开局（否则离开再回来会重置）。
      final current = ref.read(tableProvider);
      final selectedScenario = ref.read(selectedScenarioIdProvider);
      final hasLiveSession =
          current.sessionId.isNotEmpty &&
          !current.ended &&
          current.scenarioId == selectedScenario;
      if (!hasLiveSession) {
        if (current.sessionId.isNotEmpty && !current.ended) {
          await ref.read(tableProvider.notifier).endAndArchive();
        }
        await ref.read(tableProvider.notifier).start();
      }
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(tableProvider.notifier).submitPlayer(text);
  }

  /// 返回上一级：保留本局，不清空对话，下次进来继续。
  void _leave() {
    // 出错的一局不再恢复：清掉它，下次进来是干净开局（不是自动重试）。
    if (ref.read(tableProvider).status == TableStatus.error) {
      ref.invalidate(tableProvider);
    }
    context.go('/scenarios');
  }

  /// 记录：半模态展示历史，不跳路由。
  void _showTranscript() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.72,
        child: TranscriptSheet(),
      ),
    );
  }

  void _showCheckToast(Roll roll) {
    setState(() => _toastRoll = roll);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastRoll = null);
    });
  }

  void _hideCheckToast() {
    _toastTimer?.cancel();
    setState(() => _toastRoll = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableProvider);
    final notifier = ref.read(tableProvider.notifier);
    final character = ref.watch(characterProvider);
    final scenario = ref.watch(scenarioProvider).valueOrNull;

    ref.listen<TableState>(tableProvider, (previous, next) {
      if (next.inputRejected != null &&
          next.inputRejected != previous?.inputRejected) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.inputRejected!)));
      }
      if (next.dice != null && next.dice != previous?.dice) {
        _showCheckToast(next.dice!);
      }
    });

    final playerName = character.name.trim().isEmpty ? '你' : character.name;
    // 用本局实际 BP 名（对局设置里可能改过），不再读静态剧本。
    final bpNames = state.bpNames;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  sceneName: state.sceneName,
                  partySize: state.partySize,
                  canInterject: state.canInterject,
                  interjectReason: state.interjectReason ?? '现在不能插话',
                  onInterject: notifier.interject,
                  onBack: _leave,
                  onTranscript: _showTranscript,
                ),
                if (state.status == TableStatus.error)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _ErrorPanel(
                        code: state.errorCode ?? 'E_UNKNOWN',
                        message: state.errorMessage ?? '',
                        onExit: _leave,
                      ),
                    ),
                  )
                else ...[
                  // 桌子按剩余空间缩放；气泡固定在底栏上方，短就贴底，不悬空。
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxBubble = (constraints.maxHeight * 0.45).clamp(
                          96.0,
                          260.0,
                        );
                        return Column(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, tableConstraints) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: tableConstraints.maxWidth,
                                    height: 360,
                                    child: _TableArea(
                                      speaker: state.speaker,
                                      playerName: playerName,
                                      bpNames: bpNames,
                                      npcName:
                                          (scenario?.npcs.isNotEmpty ?? false)
                                          ? scenario!.npcs.first.name
                                          : 'NPC',
                                      sceneLabel:
                                          '${scenario?.title ?? ''} · ${state.sceneName}',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: maxBubble,
                                ),
                                child: _Bubble(
                                  state: state,
                                  maxHeight: maxBubble,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (_toastRoll != null)
              Positioned(
                top: 52,
                left: 16,
                right: 16,
                child: _CheckToast(
                  roll: _toastRoll!,
                  onDismiss: _hideCheckToast,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: (state.status == TableStatus.error)
          ? null
          : SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                // 键盘弹起时整条底栏上移，气泡区随之压缩。
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _BottomBar(
                  state: state,
                  controller: _controller,
                  onSend: _send,
                  onSuggestion: (suggestion) {
                    _controller.clear();
                    notifier.submitPlayer(
                      suggestion.text,
                      checkHint: suggestion.checkLabel,
                    );
                  },
                  onAdvance: notifier.advance,
                  onJournal: () => context.go('/journal'),
                ),
              ),
            ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.sceneName,
    required this.partySize,
    required this.canInterject,
    required this.interjectReason,
    required this.onInterject,
    required this.onBack,
    required this.onTranscript,
  });

  final String sceneName;
  final int partySize;
  final bool canInterject;
  final String interjectReason;
  final VoidCallback onInterject;
  final VoidCallback onBack;
  final VoidCallback onTranscript;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Text(
            sceneName,
            style: const TextStyle(fontSize: 16, letterSpacing: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '$partySize 人',
            style: const TextStyle(fontSize: 12, color: AppColors.brass),
          ),
          const Spacer(),
          Tooltip(
            message: interjectReason,
            child: OutlinedButton.icon(
              onPressed: canInterject ? onInterject : null,
              icon: const Icon(Icons.front_hand, size: 14),
              label: const Text('插话', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: canInterject
                    ? AppColors.blood
                    : AppColors.inkMuted,
                side: BorderSide(
                  color: canInterject
                      ? AppColors.blood.withValues(alpha: 0.7)
                      : const Color(0x33FFFFFF),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          IconButton(
            tooltip: '记录',
            onPressed: onTranscript,
            icon: const Icon(Icons.access_time, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 顶部检定气泡：只显示「技能 + 骰值」，3 秒自动收起，也可上滑关闭。
class _CheckToast extends StatelessWidget {
  const _CheckToast({required this.roll, required this.onDismiss});

  final Roll roll;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // 成功绿、失败红；大成功/大失败用更深的一档。
    final color = roll.outcome.isSuccess
        ? (roll.outcome == Outcome.critical
              ? const Color(0xFF1B6E2E)
              : const Color(0xFF2F7D46))
        : (roll.outcome == Outcome.fumble
              ? const Color(0xFF7A1010)
              : AppColors.blood);

    return Dismissible(
      key: ValueKey<int>(roll.seq),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss(),
      child: GestureDetector(
        onVerticalDragEnd: (_) => onDismiss(),
        child: ParchmentPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text(
                roll.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${roll.die}',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    roll.outcome.label,
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.state, required this.maxHeight});

  final TableState state;
  final double maxHeight;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _Bubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新内容进来后自动滚到底部。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final text = state.segment.isEmpty
        ? (state.busy ? '……' : '（等他开口）')
        : state.segment;

    // 预留标题/内边距/加载行的位置，剩下的才给正文，避免溢出。
    final chrome = state.busy ? 96.0 : 70.0;
    final textMax = (widget.maxHeight - chrome - 4).clamp(0.0, 200.0);

    return ParchmentPanel(
      label: state.speaker.isEmpty ? 'KP' : state.speaker,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 内容少时自收缩；超过上限才出现滚动条，且滚动条留在气泡内。
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: textMax),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: 3,
              radius: const Radius.circular(2),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(text),
                ),
              ),
            ),
          ),
          if (state.busy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: const [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '正在加载…',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B4E2E)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部固定区：选项（A./B./C. 一行一个）+ 自由输入。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.controller,
    required this.onSend,
    required this.onSuggestion,
    required this.onAdvance,
    required this.onJournal,
  });

  final TableState state;
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<ActionSuggestion> onSuggestion;
  final Future<void> Function() onAdvance;
  final VoidCallback onJournal;

  @override
  Widget build(BuildContext context) {
    if (state.status == TableStatus.ended) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: OutlinedButton(
          onPressed: onJournal,
          child: const Text('去记忆回廊看看'),
        ),
      );
    }

    if (!state.awaitingInput) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.busy ? 'AI 正在行动…' : '',
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ),
            TextButton(
              onPressed: state.busy ? null : onAdvance,
              child: const Text('继续 ▼'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < state.suggestions.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onSuggestion(state.suggestions[index]),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: Color(0x44C9A227)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    '${String.fromCharCode(65 + index)}. '
                    '${state.suggestions[index].text}'
                    '${state.suggestions[index].hasCheck ? '（${state.suggestions[index].checkLabel}）' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  // 50 字（含标点），最多 4 行，输入多少都完整显示。
                  maxLength: 50,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '你说，或者做点什么……',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSend,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brass,
                  foregroundColor: AppColors.parchmentInk,
                ),
                child: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableArea extends StatelessWidget {
  const _TableArea({
    required this.speaker,
    required this.playerName,
    required this.bpNames,
    required this.npcName,
    required this.sceneLabel,
  });

  final String speaker;
  final String playerName;
  final List<String> bpNames;
  final String npcName;
  final String sceneLabel;

  Widget _seat(
    String name,
    String role, {
    bool muted = false,
    bool highlighted = false,
    double size = 50,
  }) {
    return SeatAvatar(
      name: name,
      role: role,
      colorSeed: name.hashCode,
      muted: muted,
      size: size,
      highlighted: highlighted,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 围绕椭圆桌摆座位：KP 在上、你在下，其余人分列左右两侧。
    final others = <Widget>[
      if (bpNames.isNotEmpty)
        _seat(bpNames[0], '玩家', highlighted: speaker == bpNames[0]),
      _seat(npcName, 'NPC', muted: true, highlighted: speaker == npcName),
      if (bpNames.length > 1)
        _seat(bpNames[1], '玩家', highlighted: speaker == bpNames[1]),
      if (bpNames.length > 2)
        _seat(bpNames[2], '玩家', highlighted: speaker == bpNames[2]),
      if (bpNames.length > 3)
        _seat(bpNames[3], '玩家', highlighted: speaker == bpNames[3]),
      if (bpNames.length > 4)
        _seat(bpNames[4], '玩家', highlighted: speaker == bpNames[4]),
    ];
    const slots = <Alignment>[
      Alignment(-1, -0.32),
      Alignment(1, -0.32),
      Alignment(-1, 0.28),
      Alignment(1, 0.28),
      Alignment(-0.62, 0.78),
      Alignment(0.62, 0.78),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = (constraints.maxWidth * 0.58).clamp(170.0, 280.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: _TableSurface(label: sceneLabel, width: tableWidth),
            ),
            Align(
              alignment: const Alignment(0, -1),
              child: _seat('KP', '守秘人', highlighted: speaker == 'KP', size: 42),
            ),
            Align(
              alignment: const Alignment(0, 1),
              child: _seat(
                playerName,
                '你',
                highlighted: speaker == '你',
                size: 56,
              ),
            ),
            for (var i = 0; i < others.length; i++)
              Align(alignment: slots[i % slots.length], child: others[i]),
          ],
        );
      },
    );
  }
}

class _TableSurface extends StatelessWidget {
  const _TableSurface({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 96,
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [Color(0xFF4A3320), Color(0xFF2A1D12)],
        ),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0x55C9A227)),
        boxShadow: const [
          BoxShadow(color: Color(0x88000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 12,
              letterSpacing: 4,
              color: AppColors.brass.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.code,
    required this.message,
    required this.onExit,
  });

  final String code;
  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blood.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blood.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code == 'E_NO_KEY' ? '还没有 API key' : '这一拍没跑起来',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(message, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
            '本拍已停止，不会自动重试（避免重复消耗 token）。',
            style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => context.go('/settings'),
                child: const Text('去设置'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onExit, child: const Text('结束本局')),
            ],
          ),
        ],
      ),
    );
  }
}
