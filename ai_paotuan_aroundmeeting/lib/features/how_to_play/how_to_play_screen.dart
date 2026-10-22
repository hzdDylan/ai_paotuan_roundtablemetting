import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// 游戏说明（PRD 03 F-03：3 页以内）。
class HowToPlayScreen extends StatefulWidget {
  const HowToPlayScreen({super.key});

  @override
  State<HowToPlayScreen> createState() => _HowToPlayScreenState();
}

class _HowToPlayScreenState extends State<HowToPlayScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Page> _pages = [
    _Page(
      title: '怎么玩',
      lines: [
        '你是一个真人，桌上还有 2–5 个 AI 玩家（BP，Bot Player：由 AI 扮演的跑团玩家，坐在你旁边一起冒险，不是 NPC）和 1 个守秘人（KP）。',
        '每拍由导演决定谁说话；BP 会按自己的目标行动，也会吐槽、拒绝、临时改主意。',
        '你随时可以插话——但 KP 叙述和掷骰结算时不行。',
      ],
    ),
    _Page(
      title: '骰子',
      lines: [
        'd100 掷骰，低于等于技能值即成功。',
        '技能 ≥ 50：1–5 大成功，100 大失败。',
        '技能 < 50：只有 1 是大成功，96–100 是大失败。',
        '困难难度目标减半，极难减到五分之一。',
      ],
    ),
    _Page(
      title: '吐槽与拒绝',
      lines: [
        '你可以做任何离谱的事：把 NPC 变成鸡、在门口睡觉、对老板表白。',
        'KP 与 BP 不会说「好的你成功了」——他们会用角色的话点破你。',
        'BP 也可以拒绝你，或者为了自己的秘密突然改主意。',
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          '游 戏 说 明',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => _PageView(page: _pages[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < _pages.length; index++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == _page
                          ? AppColors.brass
                          : const Color(0x44C9A227),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Page {
  const _Page({required this.title, required this.lines});

  final String title;
  final List<String> lines;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Text(
          page.title,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 24,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 18),
        for (final line in page.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 10),
                  child: Icon(Icons.circle, size: 5, color: AppColors.brass),
                ),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
