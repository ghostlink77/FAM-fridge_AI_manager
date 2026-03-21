import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/main_bottom_nav.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

// ⚠️ 보안 경고: API 키를 앱에 직접 넣으면 누구나 추출할 수 있습니다!
// Gemini API 키는 https://aistudio.google.com/app/apikey 에서 무료로 발급받으세요

class InventoryAddOcrPage extends StatefulWidget {
  final String userId;

  const InventoryAddOcrPage({super.key, required this.userId});

  @override
  State<InventoryAddOcrPage> createState() => _InventoryAddOcrPageState();
}

class _InventoryAddOcrPageState extends State<InventoryAddOcrPage> {
  XFile? _selectedImageFile;
  Uint8List? _imageBytes;
  bool _isProcessing = false;
  String _extractedText = '';
  List<Map<String, dynamic>> _parsedItems = [];

  // 유통기한 분석 관련
  XFile? _expiryImageFile;
  Uint8List? _expiryImageBytes;
  bool _isUploadingExpiry = false;
  List<String> _expiryDates = [];

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageFile = image;
          _imageBytes = bytes;
          _extractedText = '';
          _parsedItems = [];
        });
        await _processImage();
      }
    } catch (e) {
      _showErrorMessage('이미지 선택 실패: $e');
    }
  }

  Future<void> _processImage() async {
    if (_selectedImageFile == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final imageBytes = await _selectedImageFile!.readAsBytes();

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
        requestOptions: RequestOptions(apiVersion: 'v1'),
      );

      final prompt = TextPart(
        '이 영수증 이미지에서 구매한 상품명과 수량을 JSON 배열로 추출해줘.\n'
        '형식: [{"name":"상품명","quantity":수량}]\n'
        '규칙:\n'
        '- 상품명과 수량만 추출\n'
        '- 가격, 총액, 쿠폰, 날짜, 매장명은 무시\n'
        '- 수량이 명시되지 않으면 1로 설정\n'
        '- JSON 배열만 반환 (다른 설명 없이)'
      );
      
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final content = response.text ?? '[]';

      List<Map<String, dynamic>> items = [];
      try {
        final parsedContent = jsonDecode(content) as List;
        items = parsedContent
            .map((e) => {
                  'name': e['name'] ?? '',
                  'quantity': e['quantity'] ?? 1,
                  'selected': true,
                  'expiryDate': null,
                })
            .toList();
      } catch (parseError) {
        final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
        if (jsonMatch != null) {
          final parsedContent = jsonDecode(jsonMatch.group(0)!) as List;
          items = parsedContent
              .map((e) => {
                    'name': e['name'] ?? '',
                    'quantity': e['quantity'] ?? 1,
                    'selected': true,
                    'expiryDate': null,
                  })
              .toList();
        }
      }

      setState(() {
        _parsedItems = items;
        _extractedText = content;
        _isProcessing = false;
      });

      if (items.isEmpty) {
        _showErrorMessage('상품 정보를 찾을 수 없습니다.');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showErrorMessage('이미지 분석 실패: $e');
    }
  }

  // 유통기한 이미지 선택
  Future<void> _pickExpiryImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      setState(() {
        _expiryImageFile = image;
        _expiryImageBytes = bytes;
        _expiryDates = [];
      });
      await _uploadExpiryImage(bytes, image.name);
    } catch (e) {
      _showErrorMessage('파일 선택 실패: $e');
    }
  }

  // 유통기한 이미지를 서버에 업로드
  Future<void> _uploadExpiryImage(Uint8List bytes, String fileName) async {
    setState(() => _isUploadingExpiry = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse(dotenv.env['EXPIRY_SERVER_URL'] ?? ''));
      // fromBytes 사용 — 웹 호환
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // 유통기한/소비기한만 필터링 (제조일 제외)
        final expiryLabels = {'유통기한', '소비기한'};
        final dates = (data['dates'] as List<dynamic>? ?? [])
            .where((e) => expiryLabels.contains(e['label']))
            .map((e) => e['date'] as String)
            .toList();
        setState(() {
          _expiryDates = dates;
          // 인식된 날짜를 순서대로 항목에 할당
          for (int i = 0; i < _parsedItems.length; i++) {
            _parsedItems[i]['expiryDate'] = i < dates.length ? dates[i] : null;
          }
        });
        if (dates.isEmpty) {
          _showErrorMessage('유통기한 날짜를 찾을 수 없습니다.');
        } else {
          _showSuccessMessage('유통기한 ${dates.length}개를 찾았습니다.');
        }
      } else {
        _showErrorMessage('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorMessage('서버 연결 실패: $e');
    } finally {
      setState(() => _isUploadingExpiry = false);
    }
  }

  Future<void> _saveSelectedItems() async {
    final selectedItems = _parsedItems.where((item) => item['selected'] == true).toList();
    
    if (selectedItems.isEmpty) {
      _showErrorMessage('저장할 항목을 선택해주세요.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final userInventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');

      final today = DateTime.now();
      final registrationDate = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final defaultExpiry = today.add(const Duration(days: 7));
      final defaultExpiryStr = '${defaultExpiry.year}-${defaultExpiry.month.toString().padLeft(2, '0')}-${defaultExpiry.day.toString().padLeft(2, '0')}';

      for (var item in selectedItems) {
        // 서버에서 인식한 유통기한이 있으면 사용, 없으면 기본 7일
        final expiryDateStr = (item['expiryDate'] as String?) ?? defaultExpiryStr;
        final docRef = userInventoryRef.doc();
        batch.set(docRef, {
          'name': item['name'],
          'quantity': item['quantity'],
          'registrationDate': registrationDate,
          'expiryDate': expiryDateStr,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedItems.length}개 항목이 등록되었습니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
        
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context);
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      _showErrorMessage('저장 실패: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showEditDialog(int index) {
    final item = _parsedItems[index];
    final nameController = TextEditingController(text: item['name']);
    final quantityController = TextEditingController(
      text: item['quantity'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('상품 정보 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '상품명',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(
                labelText: '수량',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = nameController.text.trim();
              final newQuantity = int.tryParse(quantityController.text) ?? 1;

              if (newName.isEmpty) {
                _showErrorMessage('상품명을 입력해주세요.');
                return;
              }

              setState(() {
                _parsedItems[index]['name'] = newName;
                _parsedItems[index]['quantity'] = newQuantity;
              });

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
            child: const Text(
              '저장',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사진으로 재고 등록'),
        backgroundColor: Colors.deepPurple,
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('처리 중...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이미지 선택 버튼
                  if (_selectedImageFile == null)
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          Icon(
                            Icons.image,
                            size: 100,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _pickImageFromGallery,
                            icon: const Icon(Icons.photo_library, color: Colors.white),
                            label: const Text(
                              '갤러리에서 선택',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 선택된 이미지
                  if (_selectedImageFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.memory(
                              _imageBytes!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_selectedImageFile!.path),
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _pickImageFromGallery,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          '다른 이미지 선택',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 파싱된 항목 리스트
                  if (_parsedItems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      '인식된 상품 (선택하여 저장):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _parsedItems.length,
                      itemBuilder: (context, index) {
                        final item = _parsedItems[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey[300]!,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: item['selected'],
                                    onChanged: (value) {
                                      setState(() {
                                        _parsedItems[index]['selected'] = value ?? false;
                                      });
                                    },
                                    activeColor: Colors.deepPurple,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['name'],
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '수량: ${item['quantity']}개',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.deepPurple),
                                      onPressed: () => _showEditDialog(index),
                                      iconSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                              // 유통기한 드롭다운 (서버에서 날짜를 인식한 경우에만 표시)
                              if (_expiryDates.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                                  child: Row(
                                    children: [
                                      Text('유통기한: ', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                      Expanded(
                                        child: DropdownButton<String>(
                                          value: item['expiryDate'] as String?,
                                          isExpanded: true,
                                          isDense: true,
                                          hint: const Text('날짜 없음', style: TextStyle(fontSize: 12)),
                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                          underline: Container(height: 1, color: Colors.deepPurple),
                                          onChanged: (val) {
                                            setState(() {
                                              _parsedItems[index]['expiryDate'] = val;
                                            });
                                          },
                                          items: [
                                            const DropdownMenuItem<String>(
                                              value: null,
                                              child: Text('날짜 없음', style: TextStyle(fontSize: 12)),
                                            ),
                                            ..._expiryDates.map((d) => DropdownMenuItem<String>(
                                                  value: d,
                                                  child: Text(d, style: const TextStyle(fontSize: 12)),
                                                )),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                    // 유통기한 분석 섹션
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('유통기한 분석',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('유통기한이 표시된 이미지를 선택하면 날짜를 자동 인식합니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    if (_expiryImageFile != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb
                              ? Image.memory(_expiryImageBytes!,
                                  width: double.infinity, height: 160, fit: BoxFit.cover)
                              : Image.file(File(_expiryImageFile!.path),
                                  width: double.infinity, height: 160, fit: BoxFit.cover),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isUploadingExpiry ? null : _pickExpiryImage,
                        icon: _isUploadingExpiry
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.document_scanner, color: Colors.deepPurple),
                        label: Text(
                          _isUploadingExpiry
                              ? '분석 중...'
                              : (_expiryImageFile == null
                                  ? '유통기한 이미지 선택'
                                  : '다른 이미지로 재분석'),
                          style: const TextStyle(color: Colors.deepPurple),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.deepPurple),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    if (_expiryDates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _expiryDates.map((d) => Chip(
                          label: Text(d, style: const TextStyle(fontSize: 12)),
                          backgroundColor: Colors.deepPurple.withValues(alpha: 0.08),
                          side: const BorderSide(color: Colors.deepPurple),
                        )).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveSelectedItems,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          '선택한 항목 저장',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
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
