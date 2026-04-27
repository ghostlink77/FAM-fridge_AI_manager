import 'package:flutter/material.dart';

class DiscardDialog extends StatefulWidget {
  final List<String> expiredItems;

  const DiscardDialog({super.key, required this.expiredItems});

  @override
  State<DiscardDialog> createState() => _DiscardDialogState();
}

class _DiscardDialogState extends State<DiscardDialog> {
  late List<Map<String, dynamic>> items;

  @override
  void initState() {
    super.initState();
    items = widget.expiredItems.map((name) => {'name': name, 'selected': true}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('폐기 처리'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return CheckboxListTile(
              value: item['selected'] as bool,
              title: Text('${item['name']}'),
              activeColor: Colors.red,
              onChanged: (val) {
                setState(() {
                  items[index]['selected'] = val ?? false;
                });
              },
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
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('폐기하기', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}