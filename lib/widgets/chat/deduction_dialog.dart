import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class DeductionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> ingredients;

  const DeductionDialog({super.key, required this.ingredients});

  @override
  State<DeductionDialog> createState() => _DeductionDialogState();
}

class _DeductionDialogState extends State<DeductionDialog> {
  late List<Map<String, dynamic>> items;

  @override
  void initState() {
    super.initState();
    items = widget.ingredients.map((e) => {
      'name': e['name'],
      'quantity': e['quantity'] ?? 1,
      'unit': e['unit'] ?? '개',
      'selected': true,
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('재고 차감'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Row(
              children: [
                Checkbox(
                  value: item['selected'] as bool,
                  onChanged: (val) {
                    setState(() {
                      items[index]['selected'] = val ?? false;
                    });
                  },
                  activeColor: AppColors.primary,
                ),
                Expanded(child: Text('${item['name']}')),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: '${item['quantity']}',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      suffixText: '${item['unit']}',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      items[index]['quantity'] = double.tryParse(val) ?? 1;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),  // 취소 → null 반환
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, items),  // 확인 → items 반환
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('차감하기', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}