/// 连通性测试端口：设置页用，不直接创建 LlmClient。
abstract interface class ConnectionTester {
  Future<void> ping({
    required String baseUrl,
    required String apiKey,
    required String model,
  });
}
