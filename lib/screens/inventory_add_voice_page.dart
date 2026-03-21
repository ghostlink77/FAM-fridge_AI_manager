import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../services/voice_api_service.dart';
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

  bool _isProcessing = false;
  String _statusMessage = '음성 파일을 선택하거나 녹음하세요';
  String _recognizedText = '';
  List<FoodItem> _extractedItems = [];

  final TextEditingController _textController = TextEditingController();

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
        type: FileType.custom,
        allowedExtensions: ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'webm', 'flac'],
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

  // ──────────────────────────────────────
  // Firestore에 추출된 항목들 저장
  // ──────────────────────────────────────
  Future<void> _saveToFirestore() async {
    if (_extractedItems.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final item in _extractedItems) {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('inventory')
            .doc();

        batch.set(docRef, {
          'name': item.name,
          'quantity': item.quantity,
          'unit': item.unit,
          'category': item.category,
          'addedAt': FieldValue.serverTimestamp(),
          'source': 'voice', // 음성 등록임을 표시
        });
      }

      await batch.commit();

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
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 상태 메시지 ──
            Card(
              color: Colors.deepPurple.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_isProcessing)
                      const CircularProgressIndicator(color: Colors.deepPurple)
                    else
                      const Icon(Icons.mic, size: 48, color: Colors.deepPurple),
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
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
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
                    icon: const Icon(Icons.send, color: Colors.deepPurple),
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
                      backgroundColor: Colors.deepPurple,
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${item.quantity} ${item.unit} · ${item.category}'),
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
