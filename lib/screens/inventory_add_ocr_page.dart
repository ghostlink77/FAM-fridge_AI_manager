import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
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
  List<String> _stateMessages = [
    '이미지 분석 중...',
    '상품명 추출 중...',
    '소비기한 계산 중...',
    '거의 완료되었습니다...',
  ];
  int _statusIndex = 0;
  Timer? _statusTimer;
  List<Map<String, dynamic>> _parsedItems = [];

  XFile? _consumeByImageFile;
  Uint8List? _consumeByImageBytes;
  bool _isUploadingConsumeBy = false;
  List<String> _unmatchedDates = [];

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

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

    _statusTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if(_statusIndex < _stateMessages.length - 1) {
        setState(() {
          _statusIndex++;
        });
      }
    });

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

      final promptTemplate = await rootBundle.loadString('assets/ocr_receipt_prompt.txt');
      final promptText = promptTemplate.replaceAll('{TODAY}', todayStr);
      final prompt = TextPart(promptText);

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
        _statusTimer?.cancel();
        _statusTimer = null;
        _statusIndex = 0;
      });

      if (items.isEmpty) {
        _showErrorMessage('상품 정보를 찾을 수 없습니다.');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusTimer?.cancel();
        _statusTimer = null;
        _statusIndex = 0;
      });
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

      final promptTemplate = await rootBundle.loadString('assets/ocr_consumeby_prompt.txt');
      final promptText = promptTemplate.replaceAll('{PRODUCT_NAMES}', namesJson);
      final prompt = TextPart(promptText);

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

  Future<void> _pickDate(int index) async {
    final currentDate = _parsedItems[index]['consumeByDate']?.toString() ?? '';
    final initialDate = _isValidDateString(currentDate)
        ? DateTime.parse(currentDate)
        : DateTime.now().add(const Duration(days: 7));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      setState(() {
        _parsedItems[index]['consumeByDate'] =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사진으로 재고 등록'),
      ),
      body: _isProcessing
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                _stateMessages[_statusIndex],
                style: TextStyle(fontSize: 20, color: AppColors.primaryDark),
              ),
            ]
          ),
        )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 40),
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
                        style: ElevatedButton.styleFrom(),
                      ),
                    ),
                  if (_selectedImageFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.memory(_imageBytes!, width: double.infinity, fit: BoxFit.cover)
                          : Image.file(File(_selectedImageFile!.path), width: double.infinity, fit: BoxFit.cover),
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
                        final consumeByDate = item['consumeByDate']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                // 체크박스
                                Checkbox(
                                  value: item['selected'] as bool,
                                  activeColor: AppColors.primary,
                                  onChanged: (value) {
                                    setState(() {
                                      _parsedItems[index]['selected'] = value ?? false;
                                    });
                                  },
                                ),
                                // 내용 영역
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 상품명
                                      Text(
                                        item['name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          // 수량 편집
                                          Text('수량: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(color: AppColors.surfaceDark),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // 마이너스 버튼
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      final current = (item['quantity'] as num?) ?? 1;
                                                      if (current > 1) {
                                                        _parsedItems[index]['quantity'] = current - 1;
                                                      }
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    child: Icon(Icons.remove, size: 16, color: AppColors.warmBrown),
                                                  ),
                                                ),
                                                // 수량 표시
                                                Container(
                                                  constraints: const BoxConstraints(minWidth: 28),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '${item['quantity'] ?? 1}',
                                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                // 플러스 버튼
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      final current = (item['quantity'] as num?) ?? 1;
                                                      _parsedItems[index]['quantity'] = current + 1;
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    child: Icon(Icons.add, size: 16, color: AppColors.warmBrown),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // 소비기한 — 탭하면 DatePicker
                                          Text('소비기한: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                          GestureDetector(
                                            onTap: () => _pickDate(index),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: AppColors.surfaceDark),
                                                borderRadius: BorderRadius.circular(6),
                                                color: consumeByDate.isNotEmpty
                                                    ? AppColors.primaryPale
                                                    : Colors.grey[100],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    consumeByDate.isNotEmpty ? consumeByDate : '없음',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: consumeByDate.isNotEmpty
                                                          ? AppColors.primaryDark
                                                          : Colors.grey,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    Icons.calendar_today,
                                                    size: 14,
                                                    color: AppColors.warmBrown,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _isUploadingConsumeBy ? null : _pickConsumeByImage,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            _isUploadingConsumeBy
                                ? const SizedBox(
                              width: 40, height: 40,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.document_scanner, size: 24, color: Color(0xFF4CAF50)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _consumeByImageFile == null ? '소비기한 이미지 인식' : '다른 이미지로 재분석',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '포장지 사진으로 소비기한을 자동 매칭',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        child: const Text(
                            '선택한 항목 저장',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _pickImageFromGallery,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        child: const Text(
                          '다른 이미지로 다시 분석',
                          style: TextStyle(color: AppColors.primary, fontSize: 16),
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
