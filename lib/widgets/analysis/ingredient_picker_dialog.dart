import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';

class IngredientPickerDialog extends StatefulWidget {
  final String userId;

  const IngredientPickerDialog({super.key, required this.userId});

  @override
  State<IngredientPickerDialog> createState() => _IngredientPickerDialogState();
}

class _IngredientPickerDialogState extends State<IngredientPickerDialog> {
  late final Future<List<Map<String, dynamic>>> _inventoryFuture;
  List<Map<String, dynamic>> _items = [];

  Future<List<Map<String, dynamic>>> _loadInventory() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('inventory')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'name': (data['name'] ?? '') as String,
        'quantity': 1,
        'unit': (data['unit'] ?? '개') as String,
        'selected': false,
        'stockQuantity': data['quantity'] ?? 0,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _inventoryFuture = _loadInventory();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('사용한 재료 선택'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '냉장고 재고에서 사용한 재료를 선택하세요',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              FutureBuilder<List<Map<String, dynamic>>>(
                future: _inventoryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  final items = snapshot.data ?? [];
                  if (_items.isEmpty && items.isNotEmpty) {
                    _items = items;
                  }

                  if (_items.isEmpty) {
                    return const Text('냉장고 재고가 없습니다');
                  }
                  return Column(
                    children: _items.map((item) =>
                        CheckboxListTile(
                          value: item['selected'] as bool,
                          onChanged: (val) {
                            setState(() {
                              item['selected'] = val ?? false;
                            });
                          },
                          title: Text('${item['name']} (재고:${item['stockQuantity']})'),
                          secondary: SizedBox(
                            width: 70,
                            child: TextFormField(
                              initialValue: item['quantity'].toString(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                suffixText: item['unit'] as String,
                                isDense: true,
                              ),
                              onChanged: (val) {
                                item['quantity'] = double.tryParse(val) ?? 1;
                              },
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        ),
                    ).toList(),
                  );
                }
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            final checkedItems = _items.where((it) => it['selected'] == true).toList();

            // 재고 초과 검사
            for (final item in checkedItems) {
              final used = (item['quantity'] as num).toDouble();
              final stock = (item['stockQuantity'] as num).toDouble();
              if (used > stock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${item['name']}: 사용 수량이 재고보다 많습니다 (재고: $stock${item['unit']})'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
            }

            // 선택한 재료가 없는 경우
            if (checkedItems.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('재료를 하나 이상 선택해주세요'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            // 결과 반환 (selected, stockQuantity는 빼고 깨끗하게)
            final result = checkedItems.map((item) => {
              'name': item['name'],
              'quantity': item['quantity'],
              'unit': item['unit'],
            }).toList();

            Navigator.pop(context, result);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('추가하기', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
