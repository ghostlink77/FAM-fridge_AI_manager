import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class ManualMealRecordPage extends StatefulWidget {
  final String userId;
  const ManualMealRecordPage({super.key, required this.userId});

  @override
  State<ManualMealRecordPage> createState() => _ManualMealRecordPageState();
}

class _ManualMealRecordPageState extends State<ManualMealRecordPage> {
  final TextEditingController _mealNameController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  String _selectedMealType = '';

  @override
  void initState() {
    super.initState();
    _selectedMealType = _getDefaultMealType();
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  String _getDefaultMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 10) return 'breakfast';
    if (hour >= 11 && hour < 14) return 'lunch';
    if (hour >= 17 && hour < 21) return 'dinner';
    return 'snack';
  }

  Widget _buildMealTypeButton(String type, String label, String timeRange) {
    final isSelected = _selectedMealType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMealType = type;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primaryDark : AppColors.surfaceDark,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: GoogleFonts.jua(
                  fontSize: 18,
                  color: isSelected ? Colors.white : AppColors.warmBrown,
                )),
            const SizedBox(height: 2),
            Text(timeRange,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.white70 : AppColors.warmBrown.withValues(alpha: 0.5),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _saveMealRecord() async {
    final mealName = _mealNameController.text.trim();
    if (mealName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('음식 이름을 입력해주세요'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('meal_records')
          .add({
        'mealName': mealName,
        'mealType': _selectedMealType,
        'mealTime': FieldValue.serverTimestamp(),
        'source': 'manual',
        'memo': _memoController.text.trim(),
        'ingredients': [],
        'nutrition': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('식사가 기록되었습니다!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);  // true를 반환해서 이전 화면에서 새로고침 가능
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('수동 식사 기록'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 음식 이름 입력
            Text('음식 이름 *',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
            const SizedBox(height: 8),
            TextField(
              controller: _mealNameController,
              decoration: InputDecoration(
                hintText: '예: 라면, 김밥, 된장찌개',
                hintStyle: TextStyle(color: AppColors.warmBrown.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // 2. 식사 시간대 선택
            Text('식사 시간대',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
              children: [
                _buildMealTypeButton('breakfast', '아침', '6:00 ~ 10:00'),
                _buildMealTypeButton('lunch', '점심', '11:00 ~ 14:00'),
                _buildMealTypeButton('dinner', '저녁', '17:00 ~ 21:00'),
                _buildMealTypeButton('snack', '야식', '21:00 ~ 6:00'),
              ],
            ),

            const SizedBox(height: 20),

            // 3. 메모
            Text('메모 (선택)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '편의점에서 사먹음, 배달 등',
                hintStyle: TextStyle(color: AppColors.warmBrown.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 24),

            // 4. 하단 버튼
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: AppColors.surfaceDark),
                    ),
                    child: Text('취소', style: TextStyle(fontSize: 16, color: AppColors.warmBrown)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saveMealRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: const Text('식사 기록 저장',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 5. AI 안내 힌트
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('💡', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('저장 시 AI가 영양 정보를 자동으로 추정합니다',
                        style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}