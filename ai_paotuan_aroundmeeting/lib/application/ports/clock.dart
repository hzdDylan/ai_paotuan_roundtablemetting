/// 应用层时钟端口。所有“现在”都从这里取，测试可注入固定时间。
abstract interface class Clock {
  DateTime now();
}

/// 生产实现：系统时间。
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
