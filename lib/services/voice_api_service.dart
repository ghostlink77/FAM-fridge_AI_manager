import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// FAM Voice API 서버와 통신하는 서비스
///
/// 사용법:
///   final service = VoiceApiService();
///   final result = await service.sendVoiceFile('/path/to/audio.wav');
///   if (result.success) {
///     print(result.text);   // "사과 세 개랑 우유 두 팩"
///     print(result.items);  // [{name: 사과, quantity: 3, unit: 개, category: 과일}, ...]
///   }
class VoiceApiService {
  // ★ 서버 주소 — 조원이 서버를 배포하면 이 주소를 변경하세요
  // 로컬 테스트 시: 'http://10.0.2.2:8000' (Android 에뮬레이터)
  //                'http://localhost:8000' (Chrome 웹)
  //                'http://PC의IP:8000' (실제 기기)
  static const String _baseUrl = 'http://localhost:8000';

  /// 서버가 살아있는지 확인
  Future<bool> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 음성 파일을 서버로 보내고 결과를 받아옴 (웹 호환)
  ///
  /// [audioBytes] 음성 파일의 바이트 데이터
  /// [fileName] 파일명 (확장자 포함, 예: "recording.m4a")
  Future<VoiceApiResult> sendVoiceBytes(Uint8List audioBytes, String fileName) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/stt');
      final request = http.MultipartRequest('POST', uri);

      // 바이트로 파일 첨부 (웹에서도 동작)
      request.files.add(
        http.MultipartFile.fromBytes(
          'audio_file',
          audioBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      final responseBody = await streamedResponse.stream.bytesToString();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      if (json['success'] == true) {
        final items = (json['items'] as List).map((item) {
          return FoodItem(
            name: item['name'] as String,
            quantity: (item['quantity'] as num).toDouble(),
            unit: item['unit'] as String,
            category: item['category'] as String,
            consumeByDate: item['consumeByDate'] as String?,
          );
        }).toList();

        return VoiceApiResult(
          success: true,
          text: json['text'] as String,
          items: items,
        );
      } else {
        return VoiceApiResult(
          success: false,
          text: '',
          items: [],
          error: json['error'] as String? ?? '서버 처리 실패',
        );
      }
    } catch (e) {
      return VoiceApiResult(
        success: false,
        text: '',
        items: [],
        error: '서버 연결 실패: $e',
      );
    }
  }

  /// 텍스트를 직접 보내서 NER만 수행 (STT 건너뜀, 테스트용)
  Future<VoiceApiResult> sendText(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ner'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 15));

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['success'] == true) {
        final items = (json['items'] as List).map((item) {
          return FoodItem(
            name: item['name'] as String,
            quantity: (item['quantity'] as num).toDouble(),
            unit: item['unit'] as String,
            category: item['category'] as String,
            consumeByDate: item['consumeByDate'] as String?,
          );
        }).toList();
        return VoiceApiResult(success: true, text: json['text'] as String, items: items);
      } else {
        return VoiceApiResult(success: false, text: text, items: [], error: json['error'] as String?);
      }
    } catch (e) {
      return VoiceApiResult(success: false, text: text, items: [], error: '서버 연결 실패: $e');
    }
  }
}

/// 서버 응답 결과
class VoiceApiResult {
  final bool success;
  final String text;       // STT 변환된 텍스트
  final List<FoodItem> items; // 추출된 음식 목록
  final String? error;

  VoiceApiResult({
    required this.success,
    required this.text,
    required this.items,
    this.error,
  });
}

/// 추출된 음식 항목
class FoodItem {
  String name;
  double quantity;
  String unit;
  String category;
  String? consumeByDate;

  FoodItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.consumeByDate,
  });
}
