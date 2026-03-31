import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import '../widgets/main_bottom_nav.dart';

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

  Map<DateTime, List<String>> _buildConsumeByMap(QuerySnapshot? snapshot) {
    final map = <DateTime, List<String>>{};
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
        map[key]!.add(name);
      }
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('소비기한 캘린더'),
        backgroundColor: Colors.deepPurple,
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
                    return Positioned(
                      bottom: 1,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: events.take(2).map((event) {
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              event.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 8),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
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

  Widget _buildSelectedDayList(Map<DateTime, List<String>> consumeByMap) {
    if (_selectedDay == null) {
      return const Center(child: Text('날짜를 선택하면 만료 예정 식품이 표시됩니다'));
    }

    final key = DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final items = consumeByMap[key] ?? [];

    if (items.isEmpty) {
      return Center(child: Text('${_selectedDay!.month}/${_selectedDay!.day} - 만료 예정 식품 없음'));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.red),
            title: Text(items[index]),
            subtitle: Text(
              '${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')} 만료',
            ),
          ),
        );
      },
    );
  }
}
