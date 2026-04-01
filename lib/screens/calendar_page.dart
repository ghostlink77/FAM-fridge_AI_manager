import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import '../theme/app_colors.dart';
import '../widgets/main_bottom_nav.dart';
import '../utils/freshness_utils.dart';

class CalendarItem {
  final String name;
  final String consumeByDate;

  CalendarItem({required this.name, required this.consumeByDate});
}

class CalendarPage extends StatefulWidget {
  final String userId;

  const CalendarPage({super.key, required this.userId});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<String> _extractConsumeByDates(Map<String, dynamic> data) {
    final dates = <String>[];

    final consumeByDatesRaw = data['consumeByDates'];
    if (consumeByDatesRaw is List) {
      for (final date in consumeByDatesRaw) {
        final text = date?.toString().trim();
        if (text != null && DateTime.tryParse(text) != null) {
          dates.add(text);
        }
      }
    }

    final singleDate = data['consumeByDate']?.toString().trim();
    if (singleDate != null && DateTime.tryParse(singleDate) != null) {
      dates.add(singleDate);
    }

    return dates.toSet().toList()..sort();
  }

  Map<DateTime, List<CalendarItem>> _buildConsumeByMap(QuerySnapshot? snapshot) {
    final map = <DateTime, List<CalendarItem>>{};
    if (snapshot == null) return map;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['name'] ?? '';
      final dateStrings = _extractConsumeByDates(data);

      for (final dateStr in dateStrings) {
        final parsed = DateTime.tryParse(dateStr);
        if (parsed == null) continue;
        final key = DateTime.utc(parsed.year, parsed.month, parsed.day);
        map.putIfAbsent(key, () => []);
        map[key]!.add(CalendarItem(name: name, consumeByDate: dateStr));
      }
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('소비기한 캘린더'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('inventory')
            .snapshots(),
        builder: (context, snapshot) {
          final consumeByMap = _buildConsumeByMap(snapshot.data);

          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                headerStyle: const HeaderStyle(formatButtonVisible: false),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  todayTextStyle: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.bold,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  defaultDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  weekendDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  outsideDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
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
                eventLoader: (day) {
                  final key = DateTime.utc(day.year, day.month, day.day);
                  return consumeByMap[key] ?? [];
                },
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    if (events.isEmpty) return null;
                    // events는 CalendarItem 리스트
                    final items = events.cast<CalendarItem>();
                    return Positioned(
                      bottom: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: items.take(4).map((item) {
                          final status = getFreshStatus(item.consumeByDate);
                          return Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(50),
                              color: getStatusColor(status),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildSelectedDayList(consumeByMap)),
            ],
          );
        },
      ),
      bottomNavigationBar: MainBottomNav(currentIndex: 0, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildSelectedDayList(Map<DateTime, List<CalendarItem>> consumeByMap) {
    if (_selectedDay == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 48, color: AppColors.primaryLight),
            const SizedBox(height: 12),
            Text(
              '날짜를 선택하면\n만료 예정 식품이 표시됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final key = DateTime.utc(
      _selectedDay!.year,
      _selectedDay!.month,
      _selectedDay!.day,
    );
    final items = consumeByMap[key] ?? [];

    if (items.isEmpty) {
      return Center(
        child: Text(
          '${_selectedDay!.month}/${_selectedDay!.day} - 만료 예정 식품 없음',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final status = getFreshStatus(item.consumeByDate);
        final daysLeft = getDaysLeft(item.consumeByDate);
        final ddayText = getDdayText(item.consumeByDate);
        final statusColor = getStatusColor(status);
        final statusBgColor = getStatusBgColor(status);

        // 소비기한 상태 텍스트
        String subtitle;
        if (daysLeft == 0) {
          subtitle = '오늘 만료!';
        } else if (daysLeft < 0) {
          subtitle = '${-daysLeft}일 경과';
        } else if (daysLeft <= 3) {
          subtitle = '$daysLeft일 남음';
        } else {
          subtitle = '여유 있음';
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: statusColor, width: 4),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    ddayText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '소비기한 ${item.consumeByDate} · $subtitle',
                        style: TextStyle(fontSize: 12, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
