/// 应用层统一失败：UI 只认识 code + 可读消息，不认识 HTTP/JSON 异常。
final class AppFailure implements Exception {
  const AppFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AppFailure($code): $message';
}
