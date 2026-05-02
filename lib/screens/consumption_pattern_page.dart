import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/main_bottom_nav.dart';
import '../theme/app_colors.dart';
import 'manual_meal_record_page.dart';

class ConsumptionPatternPage extends StatefulWidget {
  final String userId;
  const ConsumptionPatternPage({
        super.key,
        required this.userId
  });

  @override
  State<ConsumptionPatternPage> createState() => _ConsumptionPatternPageState();
}

class _ConsumptionPatternPageState extends State<ConsumptionPatternPage> {
  int _totalMeals = 0;
  Map<String, int> _mealTypeCounts = {
    'breakfast': 0, 'lunch': 0, 'dinner': 0, 'snack': 0
  };
  double _avgCalories = 0;
  double _avgProtein = 0;
  double _avgCarbs = 0;
  double _avgFat = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();  // 페이지 열릴 때 데이터 로드
  }
  Future<void> _loadData() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('meal_records')
        .orderBy('mealTime', descending: true)
        .get();

    int totalMeals = 0;
    Map<String, int> mealTypeCounts = {
      'breakfast': 0, 'lunch': 0, 'dinner': 0, 'snack': 0
    };
    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;
    int nutritionCount = 0;  // nutrition이 있는 기록만 카운트

    for (var doc in snapshot.docs) {
      final data = doc.data();
      totalMeals++;

      // mealType 카운트
      final type = data['mealType'] as String? ?? 'snack';
      mealTypeCounts[type] = (mealTypeCounts[type] ?? 0) + 1;

      // 영양 정보 합산 (nutrition이 있는 경우만)
      final nutrition = data['nutrition'] as Map<String, dynamic>?;
      if (nutrition != null) {
        totalCalories += (nutrition['calories'] as num?)?.toDouble() ?? 0;
        totalProtein += (nutrition['protein'] as num?)?.toDouble() ?? 0;
        totalCarbs += (nutrition['carbs'] as num?)?.toDouble() ?? 0;
        totalFat += (nutrition['fat'] as num?)?.toDouble() ?? 0;
        nutritionCount++;
      }
    }

    setState(() {
      _totalMeals = totalMeals;
      _mealTypeCounts = mealTypeCounts;
      if (nutritionCount > 0) {
        _avgCalories = totalCalories / nutritionCount;
        _avgProtein = totalProtein / nutritionCount;
        _avgCarbs = totalCarbs / nutritionCount;
        _avgFat = totalFat / nutritionCount;
      }
      _isLoading = false;
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('소비패턴 분석'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())  // 로딩 중
          : SingleChildScrollView(  // 로딩 완료 → 대시보드 표시
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text('총 식사 횟수',
                            style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                        const SizedBox(height: 4),
                        Text('$_totalMeals회',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.freshBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text('일평균 칼로리',
                            style: TextStyle(fontSize: 11, color: Colors.green[800])),
                        const SizedBox(height: 4),
                        Text('${_avgCalories.round()}kcal',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.green[900])),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDark, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('식사 시간대 패턴',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildMealBar('아침', _mealTypeCounts['breakfast'] ?? 0),
                        const SizedBox(width: 10),
                        _buildMealBar('점심', _mealTypeCounts['lunch'] ?? 0),
                        const SizedBox(width: 10),
                        _buildMealBar('저녁', _mealTypeCounts['dinner'] ?? 0),
                        const SizedBox(width: 10),
                        _buildMealBar('야식', _mealTypeCounts['snack'] ?? 0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDark, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('영양 균형 (일평균)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                  const SizedBox(height: 12),
                  // 탄단지 수치
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text('탄수화물', style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                            const SizedBox(height: 2),
                            Text('${_avgCarbs.round()}g',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('단백질', style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                            const SizedBox(height: 2),
                            Text('${_avgProtein.round()}g',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.accent)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('지방', style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                            const SizedBox(height: 2),
                            Text('${_avgFat.round()}g',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.danger)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 비율 바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          Expanded(flex: (_avgCarbs > 0 ? _avgCarbs.round() : 1), child: Container(color: AppColors.primary)),
                          Expanded(flex: (_avgProtein > 0 ? _avgProtein.round() : 1), child: Container(color: AppColors.accent)),
                          Expanded(flex: (_avgFat > 0 ? _avgFat.round() : 1), child: Container(color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 퍼센트 표시
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_getNutritionPercent(_avgCarbs), style: TextStyle(fontSize: 10, color: AppColors.warmBrown)),
                      Text(_getNutritionPercent(_avgProtein), style: TextStyle(fontSize: 10, color: AppColors.warmBrown)),
                      Text(_getNutritionPercent(_avgFat), style: TextStyle(fontSize: 10, color: AppColors.warmBrown)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
// 식재료 폐기 현황 카드 (Phase 2 예정)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceDark, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('식재료 폐기 현황',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('폐기 기록이 아직 없습니다',
                        style: TextStyle(fontSize: 12, color: AppColors.warmBrown)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryLight, width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('AI', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 식습관 피드백',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                        const SizedBox(height: 4),
                        Text(
                          _totalMeals < 3
                              ? '식사 기록이 3건 이상 쌓이면 AI가 식습관을 분석해드립니다.'
                              : 'AI 피드백을 불러오는 중...',
                          style: TextStyle(fontSize: 12, color: AppColors.warmBrown, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ManualMealRecordPage(userId: widget.userId),
                        ),
                      );
                      if (result == true) {
                        _loadData();  // 저장 성공하고 돌아오면 새로고침
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPale,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.restaurant, color: Colors.white, size: 24),
                          ),
                          const SizedBox(height: 10),
                          Text('수동 식사 기록',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                          const SizedBox(height: 2),
                          Text('직접 식사 내용 입력',
                              style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: 식사 캘린더 화면으로 이동
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPale,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.calendar_month, color: Colors.white, size: 24),
                          ),
                          const SizedBox(height: 10),
                          Text('요리 기록 캘린더',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
                          const SizedBox(height: 2),
                          Text('날짜별 식사 기록 확인',
                              style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: MainBottomNav(currentIndex: 3, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildMealBar(String label, int count) {
    final maxCount = _mealTypeCounts.values.fold(0, (a, b) => a > b ? a : b);
    final ratio = maxCount > 0 ? count / maxCount : 0.0;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Container(
            height: 80 * ratio,
            decoration: BoxDecoration(
              color: count > 0 ? AppColors.primary : AppColors.surfaceDark,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
        ],
      ),
    );
  }

  String _getNutritionPercent(double value) {
    final total = _avgCarbs + _avgProtein + _avgFat;
    if (total <= 0) return '0%';
    return '${(value / total * 100).round()}%';
  }
}