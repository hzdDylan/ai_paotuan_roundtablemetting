import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 系统返回键 / 侧滑返回：回到上一级页面，而不是退出应用。
///
/// 用法：在路由层包住非首页页面。首页不包，这样在首页按返回才会退出 App。
class BackScope extends StatelessWidget {
  const BackScope({super.key, required this.child, this.fallback = '/'});

  final Widget child;

  /// 没有可返回层级时去哪。
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallback);
      },
      child: child,
    );
  }
}
