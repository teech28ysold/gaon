import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:http_parser/http_parser.dart';

class ApiService {
  // FastAPI 서버 주소
  static String get baseUrl {
    return 'https://gaon-l0t5.onrender.com';
  }

  // 1. 대화 내역 가져오기
  static Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/history'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((item) => Map<String, dynamic>.from(item)).toList();
      } else {
        throw Exception('서버가 에러 코드를 반환했습니다: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('서버 연결 실패 (주소: $baseUrl). 백엔드가 실행 중인지 확인하세요. 상세: $e');
    }
  }

  // 2. 메시지 전송 및 가온 AI 응답 획득
  static Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      final bodyMap = {
        'message': message,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyMap),
      );
      
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception('서버가 에러 코드를 반환했습니다: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('서버 연결 실패 (주소: $baseUrl). 백엔드가 실행 중인지 확인하세요. 상세: $e');
    }
  }

  // 3. 대화 내역 전체 초기화
  static Future<void> clearHistory() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/api/chat/clear'));
      if (response.statusCode != 200) {
        throw Exception('서버가 에러 코드를 반환했습니다: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('서버 연결 실패 (주소: $baseUrl). 백엔드가 실행 중인지 확인하세요. 상세: $e');
    }
  }

  // 4. 이미지 전송 및 가온 AI 분석 응답 획득
  static Future<Map<String, dynamic>> sendChatImage(List<int> bytes, String filename) async {
    try {
      final uri = Uri.parse('$baseUrl/api/chat/image');
      final request = http.MultipartRequest('POST', uri);
      
      final ext = filename.split('.').last.toLowerCase();
      var mimeType = 'image/jpeg';
      if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'gif') {
        mimeType = 'image/gif';
      }

      // Multipart 파일 추가
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      );
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(utf8.decode(response.bodyBytes)));
      } else {
        throw Exception('서버가 에러 코드를 반환했습니다: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('이미지 업로드 및 분석 실패 (주소: $baseUrl). 상세: $e');
    }
  }
}
