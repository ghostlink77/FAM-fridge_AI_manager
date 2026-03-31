import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
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
  List<String> _unmatchedDates = [];

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
      final productNames = _parsedItems
          .map((e) => e['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final namesJson = jsonEncode(productNames);

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
        requestOptions: RequestOptions(apiVersion: 'v1'),
      );

      final prompt = TextPart(
        '이 이미지는 아래 상품들의 포장 사진입니다.\n'
        '상품 목록: $namesJson\n\n'
        '아래 형식의 JSON으로 반환해줘:\n'
        '{\n'
        '  "matched": {"상품명": "YYYY-MM-DD", ...},\n'
        '  "unmatched": ["YYYY-MM-DD", ...]\n'
        '}\n'
        '규칙:\n'
        '- 소비기한 또는 유통기한만 추출 (제조일 제외)\n'
        '- 목록의 상품과 매칭되면 matched에, 매칭 안 되면 unmatched 배열에 포함\n'
        '- 상품명이 완전히 같지 않아도 유사하면 matched로 처리\n'
        '- 이미지에서 찾을 수 없는 상품은 matched에서 null로 설정\n'
        '- 날짜는 반드시 YYYY-MM-DD 형식\n'
        '- JSON만 반환',
      );

      final response = await model.generateContent([
        Content.multi([
          prompt,
          DataPart('image/jpeg', bytes),
        ]),
      ]);

      final content = response.text ?? '{}';
      Map<String, dynamic> parsed = {};

      try {
        parsed = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
        if (jsonMatch != null) {
          parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        }
      }

      final matched = (parsed['matched'] as Map<String, dynamic>?) ?? {};
      final unmatched = ((parsed['unmatched'] as List<dynamic>?) ?? [])
          .map((e) => e?.toString())
          .where((e) => _isValidDateString(e))
          .toList();

      setState(() {
        for (int i = 0; i < _parsedItems.length; i++) {
          final name = _parsedItems[i]['name']?.toString() ?? '';
          final date = matched[name]?.toString();
          if (_isValidDateString(date)) {
            _parsedItems[i]['consumeByDate'] = date;
          }
        }
        _unmatchedDates = unmatched.cast<String>();
      });

      final matchedCount = matched.values.where((v) => _isValidDateString(v?.toString())).length;
      if (matchedCount == 0 && unmatched.isEmpty) {
        _showErrorMessage('소비기한 날짜를 찾을 수 없습니다.');
      } else {
        final msg = StringBuffer('소비기한 ${matchedCount}개 매칭 완료.');
        if (unmatched.isNotEmpty) {
          msg.write(' 미매칭 날짜 ${unmatched.length}개를 직접 배정해주세요.');
        }
        _showSuccessMessage(msg.toString());
      }
    } catch (e) {
      _showErrorMessage('소비기한 인식 실패: $e');
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

  Future<void> _showAssignDialog(String date) async {
    final names = _parsedItems
        .map((e) => e['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return;

    String? selected = names.first;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('날짜 배정: $date'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: names
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            onChanged: (v) => setDialogState(() => selected = v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final idx = _parsedItems.indexWhere(
                  (e) => e['name']?.toString() == selected,
                );
                if (idx != -1) {
                  _parsedItems[idx]['consumeByDate'] = date;
                }
                _unmatchedDates.remove(date);
              });
              Navigator.pop(context);
            },
            child: const Text('배정'),
          ),
        ],
      ),
    );
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
                    if (_unmatchedDates.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('미매칭 날짜', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text(
                        '상품과 연결되지 않은 날짜입니다. 배정 버튼을 눌러 직접 연결하세요.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      ..._unmatchedDates.map((date) => Card(
                            color: Colors.orange.shade50,
                            child: ListTile(
                              leading: const Icon(Icons.calendar_today, color: Colors.orange),
                              title: Text(date),
                              trailing: TextButton(
                                onPressed: () => _showAssignDialog(date),
                                child: const Text('배정'),
                              ),
                            ),
                          )),
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
