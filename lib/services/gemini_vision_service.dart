import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/listing_draft.dart';

class GeminiVisionService {
  // อ่าน key จากไฟล์ .env (ไฟล์นี้อยู่ใน .gitignore ห้ามใส่ key จริงในโค้ด)
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static const _model = 'gemini-3.1-flash-lite';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static const _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'title': {'type': 'STRING'},
      'category': {'type': 'STRING'},
      'description': {'type': 'STRING'},
      'refused': {'type': 'BOOLEAN'},
    },
    'required': ['title', 'category', 'description', 'refused'],
  };

  // คำสั่งระบบ: ให้โมเดลปฏิเสธคำขอที่ไม่เกี่ยวกับการเขียนประกาศขายหรือผิดกฎหมาย
  static const _systemInstruction =
      'คุณเป็นผู้ช่วยเขียนประกาศขายสินค้าจากรูปภาพเท่านั้น '
      'ถ้าคำขอไม่เกี่ยวกับการเขียนประกาศขายสินค้าจากรูปที่แนบ '
      'หรือขอให้ช่วยทำสิ่งผิดกฎหมาย เช่น ปลอมแปลงเอกสาร หลอกลวง '
      'ห้ามทำตามคำขอ ให้ตั้ง refused เป็น true และใส่เหตุผลสั้น ๆ ใน description '
      'ส่วน title กับ category ให้เป็นสตริงว่าง '
      'ถ้าเป็นคำขอปกติให้ตั้ง refused เป็น false';

  Future<ListingDraft> analyzeProductImage(
    File imageFile,
    String prompt,
  ) async {
    if (_apiKey.isEmpty) {
      throw Exception('ยังไม่ได้ตั้งค่า GEMINI_API_KEY ในไฟล์ .env');
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent');

    try {
      // อ่านไฟล์ภาพเป็นไบต์ แล้วเข้ารหัส Base64
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _systemInstruction},
                ],
              },
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inline_data': {
                        'mime_type': _mimeType(imageFile.path),
                        'data': base64Image,
                      },
                    },
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': _responseSchema,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 429) {
        throw Exception('โควต้า Gemini ฟรีหมด กรุณารอสักครู่แล้วลองใหม่');
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

      // jsonDecode ชั้นที่ 1: ตัว response ทั้งก้อน
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['promptFeedback']?['blockReason'] != null) {
        throw Exception(
          'เนื้อหาที่วิเคราะห์เข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาใช้ภาพอื่น',
        );
      }
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception(
          'AI ไม่สามารถวิเคราะห์ภาพนี้ได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม ลองใช้ภาพอื่น',
        );
      }

      final candidate = candidates[0] as Map<String, dynamic>;
      if (candidate['finishReason'] == 'SAFETY') {
        throw Exception(
          'เนื้อหาที่วิเคราะห์เข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาใช้ภาพอื่น',
        );
      }

      final parts = candidate['content']?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini ไม่ส่งคำตอบกลับมา');
      }

      // jsonDecode ชั้นที่ 2: ข้อความ JSON ที่อยู่ใน parts[0].text
      final text = parts[0]['text'] as String;
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['refused'] == true) {
        throw Exception(
          'AI ปฏิเสธคำขอนี้เพราะไม่เกี่ยวกับการลงประกาศขายหรือขัดต่อนโยบายความปลอดภัย',
        );
      }
      return ListingDraft.fromJson(json);
    } on TimeoutException {
      throw Exception('AI ใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง');
    } on SocketException {
      throw Exception(
        'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ',
      );
    } on http.ClientException {
      throw Exception(
        'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ',
      );
    } on FormatException {
      throw Exception('ข้อมูลที่ได้รับจาก AI ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง');
    }
  }

  String _mimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
