import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import '../theme/app_colors.dart';

class MealCalendarPage extends StatefulWidget {
  final String userId;

  const MealCalendarPage({super.key, required this.userId});

  @override
  State<MealCalendarPage> createState() => _MealCalendarPageState();
}

class _MealCalendarPageState extends State<MealCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// 식사 종류별 색상 매핑 (DB에 저장된 영어 키 사용)
  /// (breakfast=노랑, lunch=주황, dinner=빨강, snack=보라)
  static const Map<String, Color> _mealTypeColors = {
    'breakfast': Color(0xFFFFC107), // 앰버
    'lunch': Color(0xFFFF9800),     // 오렌지
    'dinner': Color(0xFFE53935),    // 레드
    'snack': Color(0xFF7E57C2),     // 퍼플
  };

  /// 화면 표시용 한국어 라벨
  static const Map<String, String> _mealTypeLabels = {
    'breakfast': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'snack': '야식',
  };

  /// 식사 종류별 정렬 우선순위 (셀 안에서 시간순으로 보이게)
  static const Map<String, int> _mealTypeOrder = {
    'breakfast': 0,
    'lunch': 1,
    'dinner': 2,
    'snack': 3,
  };

  /// Firestore 문서들을 날짜별로 그룹화
  /// 키: DateTime(연,월,일) - UTC 자정 기준
  /// 값: 그날의 식사 기록 리스트 (시간대 순으로 정렬됨)
  Map<DateTime, List<Map<String, dynamic>>> _groupByDate(QuerySnapshot? snapshot) {
    final map = <DateTime, List<Map<String, dynamic>>>{};
    if (snapshot == null) return map;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['mealTime'];
      if (ts is! Timestamp) continue; // 아직 서버 timestamp 안 찍힌 것은 스킵

      final date = ts.toDate();
      final key = DateTime.utc(date.year, date.month, date.day);
      map.putIfAbsent(key, () => []);
      map[key]!.add({
        'mealName': data['mealName'] ?? '',
        'mealType': data['mealType'] ?? '',
        'source': data['source'] ?? '',
        'docId': doc.id,
      });
    }

    // 각 날짜의 식사를 시간대 순으로 정렬
    for (final list in map.values) {
      list.sort((a, b) {
        final orderA = _mealTypeOrder[a['mealType']] ?? 99;
        final orderB = _mealTypeOrder[b['mealType']] ?? 99;
        return orderA.compareTo(orderB);
      });
    }

    return map;
  }

  /// 캘린더 셀 하나를 그리는 빌더
  /// [isToday], [isSelected], [isOutside] 따라 스타일 분기
  Widget _buildDayCell(
    DateTime day,
    Map<DateTime, List<Map<String, dynamic>>> mealMap, {
    bool isToday = false,
    bool isSelected = false,
    bool isOutside = false,
  }) {
    final key = DateTime.utc(day.year, day.month, day.day);
    final meals = mealMap[key] ?? [];

    // 셀 테두리/배경 스타일 결정
    Color borderColor = Colors.transparent;
    Color backgroundColor = Colors.transparent;
    if (isSelected) {
      borderColor = AppColors.primaryDark;
      backgroundColor = AppColors.primaryPale;
    } else if (isToday) {
      borderColor = AppColors.primary;
      backgroundColor = Colors.white;
    }

    // 날짜 숫자 색상
    Color dateColor;
    if (isOutside) {
      dateColor = AppColors.textSecondary.withValues(alpha: 0.4);
    } else if (isSelected) {
      dateColor = AppColors.primaryDark;
    } else if (isToday) {
      dateColor = AppColors.primary;
    } else {
      dateColor = AppColors.textPrimary;
    }

    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 날짜 숫자
          Text(
            '${day.day}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.w500,
              color: dateColor,
            ),
          ),
          const SizedBox(height: 1),
          // 식사 카드들 (최대 3개 + 더 있으면 +N)
          if (!isOutside) Expanded(child: _buildMealChips(meals)),
        ],
      ),
    );
  }

  /// 셀 안의 식사 카드 리스트
  /// 3개 초과 시 마지막은 "+N"으로 축약
  Widget _buildMealChips(List<Map<String, dynamic>> meals) {
    if (meals.isEmpty) return const SizedBox.shrink();

    const maxVisible = 3;
    final visibleMeals = meals.take(maxVisible).toList();
    final remainingCount = meals.length - maxVisible;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ...visibleMeals.map((meal) => _mealChip(meal)),
        if (remainingCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '+$remainingCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// 식사 1건을 표현하는 작은 칩 (이름 + 종류별 색상 막대)
  Widget _mealChip(Map<String, dynamic> meal) {
    final mealType = meal['mealType'] as String;
    final mealName = meal['mealName'] as String;
    final color = _mealTypeColors[mealType] ?? AppColors.warmBrown;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border(left: BorderSide(color: color, width: 2)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        mealName.isEmpty ? '?' : mealName,
        style: TextStyle(
          fontSize: 8.5,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  /// 식사 종류별 색상을 설명하는 범례
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _mealTypeColors.entries.map((entry) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: entry.value,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _mealTypeLabels[entry.key] ?? entry.key,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('요리 기록 캘린더'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('meal_records')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final mealMap = _groupByDate(snapshot.data);

          return Column(
            children: [
              // 식사 종류별 색상 범례
              _buildLegend(),

              // 캘린더 본체
              Expanded(
                child: SingleChildScrollView(
                  child: TableCalendar(
                    firstDay: DateTime.now().subtract(const Duration(days: 365)),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    rowHeight: 95, // 셀 높이 크게 (식단표 느낌)
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: AppColors.primaryDark,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warmBrown,
                      ),
                      weekendStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger.withValues(alpha: 0.7),
                      ),
                    ),
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) {
                      _focusedDay = focusedDay;
                    },
                    // 모든 셀 빌더 커스텀 (날짜 숫자 + 식사 카드)
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, mealMap),
                      todayBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, mealMap, isToday: true),
                      selectedBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, mealMap, isSelected: true),
                      outsideBuilder: (context, day, focusedDay) =>
                          _buildDayCell(day, mealMap, isOutside: true),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
