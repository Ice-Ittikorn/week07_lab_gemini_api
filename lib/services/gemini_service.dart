import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  // อ่าน key จากไฟล์ .env (ไฟล์นี้อยู่ใน .gitignore ห้ามใส่ key จริงในโค้ด)
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static const _model = 'gemini-3.1-flash-lite';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  Future<String> generateText(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception('ยังไม่ได้ตั้งค่า GEMINI_API_KEY ในไฟล์ .env');
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent');

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 429) {
        throw Exception('โควต้า Gemini ฟรีหมด กรุณารอสักครู่หรือเปลี่ยนโมเดล');
      }
      if (response.statusCode != 200) {
        String detail = '';
        try {
          detail = ': ${jsonDecode(response.body)['error']['message']}';
        } catch (_) {}
        throw Exception(
          'เรียก Gemini ไม่สำเร็จ (สถานะ ${response.statusCode})$detail',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Gemini ไม่ส่งคำตอบกลับมา');
      }

      final parts = (candidates[0]['content']?['parts']) as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini ไม่ส่งคำตอบกลับมา');
      }
      return parts[0]['text'] as String;
    } on TimeoutException {
      throw Exception('การเชื่อมต่อหมดเวลา กรุณาลองใหม่อีกครั้ง');
    } on http.ClientException {
      throw Exception(
        'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ',
      );
    } on FormatException {
      throw Exception('ข้อมูลที่ได้รับจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    }
  }
}
