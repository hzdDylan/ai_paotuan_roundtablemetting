import 'dart:convert';

import 'package:dio/dio.dart';

/// LLM 调用失败（SE §7.3 错误码）。
class LlmException implements Exception {
  const LlmException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'LlmException($code): $message';
}

/// 一次成功调用。
class LlmResult {
  const LlmResult({
    required this.json,
    required this.raw,
    required this.promptTokens,
    required this.completionTokens,
    required this.latencyMs,
  });

  final Map<String, dynamic> json;
  final String raw;
  final int promptTokens;
  final int completionTokens;
  final int latencyMs;

  int get totalTokens => promptTokens + completionTokens;
}

/// OpenAI 兼容客户端（D-15 = B：dio + 自写 JSON 处理）。
class LlmClient {
  LlmClient({required String baseUrl, required this.apiKey, Dio? dio})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 10),
            ),
          );

  final String _baseUrl;
  final String apiKey;
  final Dio _dio;

  static String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) value = 'https://api.deepseek.com/v1';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 请求一次「必须返回 JSON」的补全。
  Future<LlmResult> chatJson({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.85,
    int maxTokens = 700,
    CancelToken? cancelToken,
  }) async {
    final startedAt = DateTime.now();
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/chat/completions',
        data: <String, dynamic>{
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'response_format': const {'type': 'json_object'},
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    }

    final data = response.data;
    final choices = data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException('E_PARSE', '响应里没有 choices');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] as String? : null;
    if (content == null || content.trim().isEmpty) {
      throw const LlmException('E_PARSE', '响应内容为空');
    }

    final usage = data?['usage'];
    final promptTokens = usage is Map
        ? (usage['prompt_tokens'] as num?) ?? 0
        : 0;
    final completionTokens = usage is Map
        ? (usage['completion_tokens'] as num?) ?? 0
        : 0;

    return LlmResult(
      json: decodeJsonObject(content),
      raw: content,
      promptTokens: promptTokens.toInt(),
      completionTokens: completionTokens.toInt(),
      latencyMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  }

  /// 连通性测试：发一个最小请求，只看能不能拿到 200。
  Future<void> ping({required String model}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/chat/completions',
        data: <String, dynamic>{
          'model': model,
          'messages': <Map<String, String>>[
            {'role': 'user', 'content': 'ping'},
          ],
          'max_tokens': 1,
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  LlmException _mapDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const LlmException('E_CANCELLED', '请求已取消');
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const LlmException('E_TIMEOUT', '请求超时');
    }
    if (error.type == DioExceptionType.connectionError) {
      return const LlmException('E_NET_DROP', '网络中断');
    }

    final status = error.response?.statusCode;
    final body = error.response?.data?.toString() ?? '';
    return switch (status) {
      401 || 403 => LlmException(
        'E_KEY_INVALID',
        'key 无效或已过期：$body',
        statusCode: status,
      ),
      404 => LlmException('E_BASE_URL', '地址或模型名不对：$body', statusCode: 404),
      429 => LlmException('E_RATE_LIMIT', '触发限流', statusCode: 429),
      final int code when code >= 500 => LlmException(
        'E_SERVER',
        '供应商故障（$code）',
        statusCode: code,
      ),
      _ => LlmException(
        'E_NET_DROP',
        '请求失败：${error.message}',
        statusCode: status,
      ),
    };
  }
}

/// 宽容解析：模型可能把 JSON 包在 ``` 里，或前后带一句解释。
Map<String, dynamic> decodeJsonObject(String raw) {
  var text = raw.trim();

  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
  if (fence != null) {
    text = fence.group(1)!.trim();
  }

  if (text.startsWith('{') && text.endsWith('}')) {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  }

  // 兜底：截取第一个 { 到最后一个 }。
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    final slice = text.substring(start, end + 1);
    final decoded = jsonDecode(slice);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  }

  throw const LlmException('E_PARSE', '返回内容不是 JSON 对象');
}
