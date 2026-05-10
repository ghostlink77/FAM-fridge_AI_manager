import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../widgets/main_bottom_nav.dart';

class InventoryAddInputPage extends StatefulWidget {
  final String userId;

  const InventoryAddInputPage({super.key, required this.userId});

  @override
  State<InventoryAddInputPage> createState() => _InventoryAddInputPageState();
}

class _InventoryAddInputPageState extends State<InventoryAddInputPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _consumeByDateController;
  late TextEditingController _registrationDateController;
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _consumeByDateController = TextEditingController();
    _registrationDateController = TextEditingController();
    _quantityController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _consumeByDateController.dispose();
    _registrationDateController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final userInventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');

      final name = _nameController.text.trim();
      final consumeByDate = _consumeByDateController.text.trim();
      final registrationDate = _registrationDateController.text.trim();
      // 소수점 수량 허용 (레시피 차감 시 1/4개 같은 케이스 대응)
      final quantity = double.parse(_quantityController.text);

      // 병합 조건: 이름 + 소비기한 둘 다 일치하는 경우에만 합침
      // (3일 전 산 대파와 오늘 산 대파를 합치지 않기 위함)
      final existingSnapshot = await userInventoryRef
          .where('name', isEqualTo: name)
          .where('consumeByDate', isEqualTo: consumeByDate)
          .limit(1)
          .get();

      if (existingSnapshot.docs.isNotEmpty) {
        final existingDoc = existingSnapshot.docs.first;
        final existingData = existingDoc.data();

        // 소수점 보존: toDouble() 사용 (이전엔 toInt()로 잘려서 0.75 등 손실)
        final existingQuantityRaw = existingData['quantity'];
        final existingQuantity = existingQuantityRaw is num
            ? existingQuantityRaw.toDouble()
            : double.tryParse(existingQuantityRaw?.toString() ?? '0') ?? 0.0;

        // 소비기한이 동일하므로 mergedDates는 항상 [consumeByDate] 한 개짜리
        // (consumeByDates 필드는 캘린더/목록 페이지가 읽으므로 형태 유지)
        await existingDoc.reference.update({
          'quantity': existingQuantity + quantity,
          'registrationDate': registrationDate,
          'consumeByDate': consumeByDate,
          'consumeByDates': [consumeByDate],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await userInventoryRef.add({
          'name': name,
          'consumeByDate': consumeByDate,
          'consumeByDates': [consumeByDate],
          'registrationDate': registrationDate,
          'quantity': quantity,
          'source': 'manual',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('재고가 등록되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );

        _formKey.currentState!.reset();
        _nameController.clear();
        _consumeByDateController.clear();
        _registrationDateController.clear();
        _quantityController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재고 등록 실패: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('재고 직접 등록'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 85),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('재고 이름', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '재고 이름을 입력하세요',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (value) => (value == null || value.isEmpty) ? '' : null,
              ),
              const SizedBox(height: 24),
              const Text('소비기한', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _consumeByDateController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: '날짜를 선택하세요',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () => _selectDate(context, _consumeByDateController),
                validator: (value) => (value == null || value.isEmpty) ? '' : null,
              ),
              const SizedBox(height: 24),
              const Text('등록 일자', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _registrationDateController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: '날짜를 선택하세요',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () => _selectDate(context, _registrationDateController),
                validator: (value) => (value == null || value.isEmpty) ? '' : null,
              ),
              const SizedBox(height: 24),
              const Text('수량', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '수량을 입력하세요',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixText: '개',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '';
                  final parsed = int.tryParse(value);
                  if (parsed == null || parsed <= 0) return '';
                  return null;
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitForm,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    '재고 등록',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: MainBottomNav(currentIndex: 1, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
