import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/voice_api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/main_bottom_nav.dart';

/// 음성으로 식료품을 등록하는 페이지
///
/// 흐름: 음성 녹음/파일 선택 → 서버 전송 → 결과 확인 → Firestore 저장
class InventoryAddVoicePage extends StatefulWidget {
  final String userId;

  const InventoryAddVoicePage({super.key, required this.userId});

  @override
  State<InventoryAddVoicePage> createState() => _InventoryAddVoicePageState();
}

class _InventoryAddVoicePageState extends State<InventoryAddVoicePage> {
  final VoiceApiService _voiceService = VoiceApiService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isProcessing = false;
  bool _isRecording = false;
  String _statusMessage = '음성 파일을 선택하거나 녹음하세요';
  String _recognizedText = '';
  List<FoodItem> _extractedItems = [];

  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────
  // 서버로 음성 바이트 전송 & 결과 받기
  // ──────────────────────────────────────
  Future<void> _processAudioBytes(Uint8List bytes, String fileName) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '서버에 음성 전송 중...';
      _recognizedText = '';
      _extractedItems = [];
    });

    final isServerUp = await _voiceService.healthCheck();
    if (!isServerUp) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '서버에 연결할 수 없습니다.\n서버가 실행 중인지 확인하세요.';
      });
      return;
    }

    setState(() => _statusMessage = 'STT + NER 처리 중...');

    final result = await _voiceService.sendVoiceBytes(bytes, fileName);
    _handleResult(result);
  }

  // ──────────────────────────────────────
  // 텍스트 직접 전송 (STT 없이 NER만 테스트)
  // ──────────────────────────────────────
  Future<void> _processText(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'NER 처리 중...';
      _recognizedText = '';
      _extractedItems = [];
    });

    final result = await _voiceService.sendText(text);
    _handleResult(result);
  }

  void _handleResult(VoiceApiResult result) {
    setState(() {
      _isProcessing = false;
      if (result.success) {
        _recognizedText = result.text;
        _extractedItems = result.items;
        _statusMessage = result.items.isEmpty
            ? '음식 항목을 찾지 못했습니다.'
            : '${result.items.length}개 항목을 찾았습니다!';
      } else {
        _statusMessage = '처리 실패: ${result.error}';
      }
    });
  }

  // ──────────────────────────────────────
  // 음성 파일 선택 (바이트로 읽어서 전송 — 웹 호환)
  // ──────────────────────────────────────
  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true, // 웹에서 바이트 데이터를 가져오기 위해 필요
      );
      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final fileName = result.files.single.name;
        await _processAudioBytes(bytes, fileName);
      }
    } catch (e) {
      setState(() {
        _statusMessage = '파일 선택 오류: $e';
      });
    }
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    final maybeName = parts.isNotEmpty ? parts.last : '';
    if (maybeName.isEmpty || maybeName.startsWith('blob:')) {
      return 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    return maybeName;
  }

  Future<void> _startRecording() async {
    if (_isProcessing || _isRecording) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _statusMessage = '마이크 권한이 필요합니다.';
        });
        return;
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _statusMessage = '음성 감지 중';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '녹음 시작 실패: $e';
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    try {
      await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _statusMessage = '음성 녹음을 취소했습니다.';
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusMessage = '녹음 취소 실패: $e';
      });
    }
  }

  Future<void> _finishRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      if (path == null || path.isEmpty) {
        setState(() {
          _statusMessage = '녹음된 파일을 찾을 수 없습니다.';
        });
        return;
      }

      Uint8List bytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        bytes = response.bodyBytes;
      } else {
        bytes = await XFile(path).readAsBytes();
      }

      await _processAudioBytes(bytes, _fileNameFromPath(path));
    } catch (e) {
      setState(() {
        _isRecording = false;
        _statusMessage = '녹음 완료 처리 실패: $e';
      });
    }
  }

  // ──────────────────────────────────────
  // Firestore에 추출된 항목들 저장
  // ──────────────────────────────────────
  Future<void> _saveToFirestore() async {
    if (_extractedItems.isEmpty) return;

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');

      final today = DateTime.now();
      final registrationDate =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // 직접입력/OCR과 동일한 병합 정책:
      // - 이름 + 소비기한이 같으면 기존 문서에 quantity 합산
      // - 소비기한이 없는 항목(음성에서 종종 발생)은 병합하지 않고 항상 새 문서로 추가
      //   (where('consumeByDate', isEqualTo: null) 매칭 모호성 회피)
      // 음성 항목은 보통 소수라 batch 대신 순차 처리해도 성능 영향 미미
      for (final item in _extractedItems) {
        final consumeByDate = item.consumeByDate;
        // item.quantity는 model에서 num 타입으로 강제되므로 toDouble() 직접 호출
        final quantity = item.quantity.toDouble();

        if (consumeByDate != null) {
          // 소비기한이 있을 때만 병합 시도
          final existingSnapshot = await inventoryRef
              .where('name', isEqualTo: item.name)
              .where('consumeByDate', isEqualTo: consumeByDate)
              .limit(1)
              .get();

          if (existingSnapshot.docs.isNotEmpty) {
            final existingDoc = existingSnapshot.docs.first;
            final existingData = existingDoc.data();
            final existingQuantityRaw = existingData['quantity'];
            final existingQuantity = existingQuantityRaw is num
                ? existingQuantityRaw.toDouble()
                : double.tryParse(existingQuantityRaw?.toString() ?? '0') ?? 0.0;

            await existingDoc.reference.update({
              'quantity': existingQuantity + quantity,
              'registrationDate': registrationDate,
              'consumeByDate': consumeByDate,
              'consumeByDates': [consumeByDate],
              'updatedAt': FieldValue.serverTimestamp(),
            });
            continue; // 다음 항목으로
          }
        }

        // 신규 추가 (소비기한 없는 케이스 또는 매칭되는 기존 문서 없음)
        await inventoryRef.add({
          'name': item.name,
          'quantity': quantity,
          'unit': item.unit,
          'category': item.category,
          'registrationDate': registrationDate,
          if (consumeByDate != null) 'consumeByDate': consumeByDate,
          if (consumeByDate != null) 'consumeByDates': [consumeByDate],
          'source': 'voice',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_extractedItems.length}개 항목이 저장되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // 이전 화면으로 돌아감
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ──────────────────────────────────────
  // UI
  // ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('음성으로 등록'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 상태 메시지 ──
            Card(
              color: AppColors.primary.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_isProcessing)
                      const CircularProgressIndicator(color: AppColors.primary)
                    else
                      const Icon(Icons.mic, size: 48, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 녹음/파일 선택 버튼 ──
            if (!_isProcessing) ...[
              ElevatedButton.icon(
                onPressed: _pickAudioFile,
                icon: const Icon(Icons.audio_file),
                label: const Text('음성 파일 선택'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isRecording ? null : _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('음성 녹음'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              if (_isRecording) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '음성 감지 중',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _cancelRecording,
                              child: const Text('취소'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _finishRecording,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('완료'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              // ── 텍스트 직접 입력 (NER 테스트용) ──
              const Divider(),
              const Text('또는 텍스트로 직접 테스트:', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: '예: 사과 세 개랑 우유 두 팩 사왔어',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send, color: AppColors.primary),
                    onPressed: () => _processText(_textController.text),
                  ),
                ),
                onSubmitted: _processText,
              ),
            ],

            // ── 인식된 텍스트 ──
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                '인식된 텍스트:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _recognizedText,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],

            // ── 추출된 항목 리스트 ──
            if (_extractedItems.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                '추출된 항목:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ..._extractedItems.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${item.quantity} ${item.unit} · ${item.category}'
                      '${item.consumeByDate != null ? ' · 소비기한 ${item.consumeByDate}' : ''}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _extractedItems.removeAt(idx);
                        });
                      },
                    ),
                  ),
                );
              }),

              // ── 저장 버튼 ──
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveToFirestore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  '${_extractedItems.length}개 항목 저장하기',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: MainBottomNav(currentIndex: 1, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
