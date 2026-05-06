import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../theme/app_colors.dart';
import '../widgets/analysis/ingredient_picker_dialog.dart';

class ManualMealRecordPage extends StatefulWidget {
  final String userId;

  const ManualMealRecordPage({super.key, required this.userId});

  @override
  State<ManualMealRecordPage> createState() => _ManualMealRecordPageState();
}

class _ManualMealRecordPageState extends State<ManualMealRecordPage> {
  final TextEditingController _mealNameController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final List<Map<String, dynamic>> _selectedIngredients = [];
  String _selectedMealType = '';
  bool _isSaving = false;

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
            Text(
              label,
              style: GoogleFonts.jua(
                fontSize: 18,
                color: isSelected ? Colors.white : AppColors.warmBrown,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeRange,
              style: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? Colors.white70
                    : AppColors.warmBrown.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gemini API로 영양 정보 추정
  /// 형식: {calories: kcal, protein: g, carbs: g, fat: g}
  /// 실패 시 null 반환 (저장 자체는 계속 진행)
  Future<Map<String, dynamic>?> _estimateNutrition(
    String mealName,
    List<Map<String, dynamic>> ingredients,
  ) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) return null;

      // ingredients를 사람이 읽기 좋은 텍스트로 변환
      final ingredientsText = ingredients.isEmpty
          ? '재료 정보 없음'
          : ingredients
              .map((it) => '${it['name']} ${it['quantity']}${it['unit']}')
              .join(', ');

      final prompt = '''
다음 음식의 영양 정보를 추정해서 JSON으로만 응답하세요.

음식명: $mealName
재료: $ingredientsText

응답 형식 (JSON 외 다른 텍스트 절대 금지):
{"calories":숫자,"protein":숫자,"carbs":숫자,"fat":숫자}

- calories: kcal 단위
- protein, carbs, fat: g 단위
- 숫자는 정수 또는 소수점 1자리
''';

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      // ```json ... ``` 마크다운 코드 블록 제거
      var jsonText = text.trim();
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replaceAll(RegExp(r'```json|```'), '').trim();
      }

      final parsed = jsonDecode(jsonText);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      return null;
    } catch (e) {
      // 영양 정보 추정 실패해도 저장은 계속
      debugPrint('영양 정보 추정 실패: $e');
      return null;
    }
  }

  /// 선택된 재료들을 inventory에서 차감
  /// (수량이 0 이하가 되면 doc 자체를 삭제)
  Future<void> _deductInventory(List<Map<String, dynamic>> itemsToDeduct) async {
    if (itemsToDeduct.isEmpty) return;

    final inventoryRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('inventory');

    final snapshot = await inventoryRef.get();

    for (final item in itemsToDeduct) {
      final itemName = item['name'] as String;
      final usedQty = (item['quantity'] as num).toDouble();

      // 같은 이름의 첫 번째 doc 찾아서 차감
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['name'] == itemName) {
          final currentQty = (data['quantity'] as num?)?.toDouble() ?? 0;
          final newQty = currentQty - usedQty;

          if (newQty <= 0) {
            await doc.reference.delete();
          } else {
            await doc.reference.update({'quantity': newQty});
          }
          break;
        }
      }
    }
  }

  Future<void> _saveMealRecord() async {
    final mealName = _mealNameController.text.trim();
    if (mealName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('음식 이름을 입력해주세요'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. 영양 정보 추정 (Gemini API)
      final nutrition = await _estimateNutrition(mealName, _selectedIngredients);

      // 2. inventory 차감
      await _deductInventory(_selectedIngredients);

      // 3. 식사 기록 저장
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
            'ingredients': _selectedIngredients,
            'nutrition': nutrition,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        final count = _selectedIngredients.length;
        final base = count > 0
            ? '식사가 기록되고 재료 $count개가 차감되었습니다'
            : '식사가 기록되었습니다!';
        final msg = nutrition != null
            ? '$base (${nutrition['calories']}kcal)'
            : base;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // true를 반환해서 이전 화면에서 새로고침 가능
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
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
            Text(
              '음식 이름 *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mealNameController,
              decoration: InputDecoration(
                hintText: '예: 라면, 김밥, 된장찌개',
                hintStyle: TextStyle(
                  color: AppColors.warmBrown.withValues(alpha: 0.5),
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. 식사 시간대 선택
            Text(
              '식사 시간대',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
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

            // 3. 재료 선택
            Text(
              '재료 추가 (선택)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceDark),
              ),
              child: Column(
                children: [
                  // 위: 칩들
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ..._selectedIngredients.map(
                        (ing) => Chip(
                          label: Text(
                            '${ing['name']} ${ing['quantity']}${ing['unit']}',
                          ),
                          onDeleted: () {
                            setState(() {
                              _selectedIngredients.remove(ing);
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  // 아래: 재료 추가
                  InkWell(
                    onTap: () async {
                      final result = await showDialog<List<Map<String, dynamic>>>(
                        context: context,
                        builder: (context) => IngredientPickerDialog(userId: widget.userId),
                      );

                      if (result != null && result.isNotEmpty && mounted) {
                        setState(() {
                          _selectedIngredients.addAll(result);
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '재료 추가...',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.warmBrown.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                          Icon(Icons.add, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 4. 메모
            Text(
              '메모 (선택)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '편의점에서 사먹음, 배달 등',
                hintStyle: TextStyle(
                  color: AppColors.warmBrown.withValues(alpha: 0.5),
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 5. 하단 버튼
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: AppColors.surfaceDark),
                    ),
                    child: Text(
                      '취소',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.warmBrown,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveMealRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '식사 기록 저장',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 6. AI 안내 힌트
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
                    child: Text(
                      '저장 시 AI가 영양 정보를 자동으로 추정합니다',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warmBrown,
                      ),
                    ),
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
