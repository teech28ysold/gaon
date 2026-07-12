import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = 'https://gaon-l0t5.onrender.com';
  static const Duration _shortTimeout = Duration(seconds: 15);
  static const Duration _longTimeout = Duration(seconds: 60);
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final data = await _requestJson(
      http.get(Uri.parse('$baseUrl/api/history')),
      timeout: _shortTimeout,
    );
    if (data is! List) {
      throw const ApiException('대화 내용을 불러오지 못했어요. 다시 시도해 주세요.');
    }
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    double? latitude,
    double? longitude,
  }) async {
    return _requestJsonMap(
      http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'message': message,
          'latitude': ?latitude,
          'longitude': ?longitude,
        }),
      ),
      timeout: _longTimeout,
      fallbackMessage: '답변을 가져오지 못했어요. 잠시 후 다시 질문해 주세요.',
    );
  }

  static Future<void> clearHistory() async {
    await _requestJson(
      http.post(Uri.parse('$baseUrl/api/chat/clear')),
      timeout: _shortTimeout,
    );
  }

  static Future<Map<String, dynamic>> sendChatImage(
    List<int> bytes,
    String filename,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/chat/image'),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(_mimeTypeFor(filename)),
        ),
      );
      final streamed = await request.send().timeout(_longTimeout);
      final response = await http.Response.fromStream(streamed);
      return _decodeMapResponse(response, '사진을 읽지 못했어요. 다시 찍어서 보내 주세요.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('사진을 보내지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
  }

  static Future<Map<String, dynamic>> sendSms(
    List<String> receivers,
    String message,
  ) async {
    return _requestJsonMap(
      http.post(
        Uri.parse('$baseUrl/api/send-sms'),
        headers: _jsonHeaders,
        body: jsonEncode({'receivers': receivers, 'message': message}),
      ),
      timeout: _shortTimeout,
      fallbackMessage: '문자를 보내지 못했어요. 보호자 번호와 인터넷 연결을 확인해 주세요.',
    );
  }

  static Future<Map<String, dynamic>> _requestJsonMap(
    Future<http.Response> request, {
    required Duration timeout,
    required String fallbackMessage,
  }) async {
    final data = await _requestJson(
      request,
      timeout: timeout,
      fallbackMessage: fallbackMessage,
    );
    if (data is! Map) {
      throw ApiException(fallbackMessage);
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<dynamic> _requestJson(
    Future<http.Response> request, {
    required Duration timeout,
    String fallbackMessage = '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
  }) async {
    try {
      final response = await request.timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_serverMessage(response, fallbackMessage));
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(fallbackMessage);
    }
  }

  static Map<String, dynamic> _decodeMapResponse(
    http.Response response,
    String fallbackMessage,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_serverMessage(response, fallbackMessage));
    }
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {
      // The caller receives the same simple, actionable message for malformed data.
    }
    throw ApiException(fallbackMessage);
  }

  static String _serverMessage(http.Response response, String fallbackMessage) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data['detail'] is String) {
        final detail = (data['detail'] as String).trim();
        if (detail.isNotEmpty && response.statusCode < 500) return detail;
      }
    } catch (_) {
      // Ignore malformed server errors and show the user-friendly fallback.
    }
    return fallbackMessage;
  }

  static String _mimeTypeFor(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }
}
