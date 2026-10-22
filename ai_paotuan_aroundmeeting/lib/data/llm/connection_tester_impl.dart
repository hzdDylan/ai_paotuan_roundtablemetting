import '../../application/ports/app_failure.dart';
import '../../application/ports/connection_tester.dart';
import '../../llm/llm_client.dart';

/// 设置页连通性测试的生产实现。
final class LlmConnectionTester implements ConnectionTester {
  const LlmConnectionTester();

  @override
  Future<void> ping({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    try {
      await LlmClient(baseUrl: baseUrl, apiKey: apiKey).ping(model: model);
    } on LlmException catch (error) {
      throw AppFailure(error.code, error.message);
    }
  }
}
