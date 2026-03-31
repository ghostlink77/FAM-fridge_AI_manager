import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../widgets/main_bottom_nav.dart';

class InventoryAddOcrPage extends StatefulWidget {
  final String userId;

  const InventoryAddOcrPage({super.key, required this.userId});

  @override
  State<InventoryAddOcrPage> createState() => _InventoryAddOcrPageState();
}

class _InventoryAddOcrPageState extends State<InventoryAddOcrPage> {
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImageFile;
  Uint8List? _imageBytes;
  bool _isProcessing = false;
  List<Map<String, dynamic>> _parsedItems = [];

  XFile? _consumeByImageFile;
  Uint8List? _consumeByImageBytes;
  bool _isUploadingConsumeBy = false;

  bool _isValidDateString(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return DateTime.tryParse(value.trim()) != null;
  }

  List<String> _extractConsumeByDates(dynamic consumeByDatesRaw, dynamic consumeByDateRaw) {
    final dates = <String>[];

    if (consumeByDatesRaw is List) {
      for (final date in consumeByDatesRaw) {
        final text = date?.toString().trim();
        if (_isValidDateString(text)) {
          dates.add(text!);
        }
      }
    }

    final singleDate = consumeByDateRaw?.toString().trim();
    if (_isValidDateString(singleDate)) {
      dates.add(singleDate!);
    }

    return dates.toSet().toList()..sort();
  }

  String _getEarliestConsumeByDate(List<String> dates) {
    if (dates.isEmpty) return '';
    final sorted = [...dates]..sort();
    return sorted.first;
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImageFile = image;
        _imageBytes = bytes;
        _parsedItems = [];
      });

      await _processImage();
    } catch (e) {
      _showErrorMessage('이미지 선택 실패: $e');
    }
  }

  Future<void> _processImage() async {
    if (_selectedImageFile == null) return;

    setState(() => _isProcessing = true);

    try {
      final imageBytes = await _selectedImageFile!.readAsBytes();
      final now = DateTime.now();
      final todayStr =
          '${now.year.toString().substring(2)}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
        requestOptions: RequestOptions(apiVersion: 'v1'),
      );

      final prompt = TextPart(
        '이 영수증 이미지에서 구매한 식품의 상품명, 수량, 소비기한을 JSON 배열로 추출해줘.\n'
        '형식: [{"name":"상품명","quantity":수량,"consumeByDate":"YYYY-MM-DD"}]\n'
        '규칙:\n'
        '- 봉투, 사무용품 등 식품이나 과자, 식자재가 아닌 항목은 제외\n'
        '- 상품명과 수량 추출 필수\n'
        '- 오늘 날짜는 $todayStr\n'
        '- 각 상품의 예상 소비기한을 계산해서 YYYY-MM-DD 형식으로 consumeByDate에 넣기\n'
        '- 소비기한 예상의 근거를 충분히 생각해 줘\n'
        '- 소비기한 추정이 어려우면 consumeByDate를 null로 반환\n'
        '- 수량이 명시되지 않으면 1로 설정\n'
        '- 가격, 총액, 쿠폰, 매장명은 무시\n'
        '- JSON 배열만 반환',
      );

      final response = await model.generateContent([
        Content.multi([
          prompt,
          DataPart('image/jpeg', imageBytes),
        ]),
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
                  'consumeByDate': e['consumeByDate'],
                })
            .toList();
      } catch (_) {
        final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
        if (jsonMatch != null) {
          final parsedContent = jsonDecode(jsonMatch.group(0)!) as List;
          items = parsedContent
              .map((e) => {
                    'name': e['name'] ?? '',
                    'quantity': e['quantity'] ?? 1,
                    'selected': true,
                    'consumeByDate': e['consumeByDate'],
                  })
              .toList();
        }
      }

      setState(() {
        _parsedItems = items;
        _isProcessing = false;
      });

      if (items.isEmpty) {
        _showErrorMessage('상품 정보를 찾을 수 없습니다.');
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showErrorMessage('이미지 분석 실패: $e');
    }
  }

  Future<void> _pickConsumeByImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      setState(() {
        _consumeByImageFile = image;
        _consumeByImageBytes = bytes;
      });

      await _uploadConsumeByImage(bytes, image.name);
    } catch (e) {
      _showErrorMessage('파일 선택 실패: $e');
    }
  }

  Future<void> _uploadConsumeByImage(Uint8List bytes, String fileName) async {
    setState(() => _isUploadingConsumeBy = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(dotenv.env['EXPIRY_SERVER_URL'] ?? ''),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final labels = {'소비기한'};
        final dates = (data['dates'] as List<dynamic>? ?? [])
            .where((e) => labels.contains(e['label']))
            .map((e) => e['date'] as String)
            .where((e) => _isValidDateString(e))
            .toList();

        setState(() {
          for (int i = 0; i < _parsedItems.length; i++) {
            _parsedItems[i]['consumeByDate'] = i < dates.length ? dates[i] : null;
          }
        });

        if (dates.isEmpty) {
          _showErrorMessage('소비기한 날짜를 찾을 수 없습니다.');
        } else {
          _showSuccessMessage('소비기한 ${dates.length}개를 찾았습니다.');
        }
      } else {
        _showErrorMessage('서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorMessage('서버 연결 실패: $e');
    } finally {
      setState(() => _isUploadingConsumeBy = false);
    }
  }

  Future<void> _saveSelectedItems() async {
    final selectedItems = _parsedItems.where((item) => item['selected'] == true).toList();
    if (selectedItems.isEmpty) {
      _showErrorMessage('저장할 항목을 선택해주세요.');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final userInventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');

      final today = DateTime.now();
      final registrationDate =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final defaultConsumeBy = today.add(const Duration(days: 7));
      final defaultConsumeByStr =
          '${defaultConsumeBy.year}-${defaultConsumeBy.month.toString().padLeft(2, '0')}-${defaultConsumeBy.day.toString().padLeft(2, '0')}';

      final mergedByName = <String, Map<String, dynamic>>{};

      for (final item in selectedItems) {
        final rawName = (item['name'] ?? '').toString().trim();
        if (rawName.isEmpty) continue;

        final quantityRaw = item['quantity'];
        final quantity = quantityRaw is num
            ? quantityRaw.toInt()
            : int.tryParse(quantityRaw.toString()) ?? 1;

        final consumeByFromItem = item['consumeByDate']?.toString();
        final itemConsumeByDates = <String>[];
        if (_isValidDateString(consumeByFromItem)) {
          itemConsumeByDates.add(consumeByFromItem!.trim());
        }

        final current = mergedByName.putIfAbsent(rawName, () {
          return {
            'quantity': 0,
            'consumeByDates': <String>[],
          };
        });

        current['quantity'] = (current['quantity'] as int) + quantity;
        (current['consumeByDates'] as List<String>).addAll(itemConsumeByDates);
      }

      for (final entry in mergedByName.entries) {
        final name = entry.key;
        final quantityToAdd = entry.value['quantity'] as int;
        final newDatesRaw =
            (entry.value['consumeByDates'] as List<String>).toSet().toList()..sort();
        final newDates = newDatesRaw.isEmpty ? [defaultConsumeByStr] : newDatesRaw;

        final existingSnapshot = await userInventoryRef
            .where('name', isEqualTo: name)
            .limit(1)
            .get();

        if (existingSnapshot.docs.isNotEmpty) {
          final existingDoc = existingSnapshot.docs.first;
          final existingData = existingDoc.data();

          final existingQuantityRaw = existingData['quantity'];
          final existingQuantity = existingQuantityRaw is num
              ? existingQuantityRaw.toInt()
              : int.tryParse(existingQuantityRaw?.toString() ?? '0') ?? 0;

          final existingDates = _extractConsumeByDates(
            existingData['consumeByDates'],
            existingData['consumeByDate'],
          );

          final mergedDates = {...existingDates, ...newDates}.toList()..sort();
          final earliestDate = _getEarliestConsumeByDate(mergedDates);

          batch.update(existingDoc.reference, {
            'quantity': existingQuantity + quantityToAdd,
            'registrationDate': registrationDate,
            'consumeByDate': earliestDate,
            'consumeByDates': mergedDates,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final docRef = userInventoryRef.doc();
          final earliestDate = _getEarliestConsumeByDate(newDates);

          batch.set(docRef, {
            'name': name,
            'quantity': quantityToAdd,
            'registrationDate': registrationDate,
            'consumeByDate': earliestDate,
            'consumeByDates': newDates,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${mergedByName.length}개 항목이 등록되었습니다.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showErrorMessage('저장 실패: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedImageFile == null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _pickImageFromGallery,
                        icon: const Icon(Icons.photo_library, color: Colors.white),
                        label: const Text('갤러리에서 선택', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      ),
                    ),
                  if (_selectedImageFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.memory(_imageBytes!, width: double.infinity, fit: BoxFit.cover)
                          : Image.file(File(_selectedImageFile!.path), width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _pickImageFromGallery,
                      child: const Text('다른 이미지 선택'),
                    ),
                  ],
                  if (_parsedItems.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('인식된 항목', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _parsedItems.length,
                      itemBuilder: (context, index) {
                        final item = _parsedItems[index];
                        return Card(
                          child: ListTile(
                            leading: Checkbox(
                              value: item['selected'] as bool,
                              onChanged: (value) {
                                setState(() {
                                  _parsedItems[index]['selected'] = value ?? false;
                                });
                              },
                            ),
                            title: Text(item['name']?.toString() ?? ''),
                            subtitle: Text('수량: ${item['quantity']} / 소비기한: ${item['consumeByDate'] ?? '없음'}'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isUploadingConsumeBy ? null : _pickConsumeByImage,
                      icon: _isUploadingConsumeBy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner),
                      label: Text(_consumeByImageFile == null ? '소비기한 이미지 선택' : '다른 이미지로 재분석'),
                    ),
                    if (_consumeByImageFile != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.memory(_consumeByImageBytes!, height: 120, fit: BoxFit.cover)
                            : Image.file(File(_consumeByImageFile!.path), height: 120, fit: BoxFit.cover),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSelectedItems,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                        child: const Text('선택한 항목 저장', style: TextStyle(color: Colors.white)),
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
