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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('유통기한 캘린더'),
        backgroundColor: Colors.deepPurple,
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('inventory')
            .snapshots(),
        builder: (context, snapshot) {
          // snapshot에서 데이터를 꺼내서 Map으로 변환
          final expiryMap = _buildExpiryMap(snapshot.data);

          return Column(
            children:[
              TableCalendar(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
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
                  // 날짜를 UTC로 통일해서 Map에서 조회
                  final key = DateTime.utc(day.year, day.month, day.day);
                  return expiryMap[key] ?? [];
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                              ),
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
              Expanded(
                child: _buildSelectedDayList(expiryMap),
              ),
            ]
          );


        },
      ),

      bottomNavigationBar: MainBottomNav(
          currentIndex: 0,
          userId: widget.userId
      ),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Map<DateTime, List<String>> _buildExpiryMap(QuerySnapshot? snapshot){
    final map = <DateTime, List<String>>{};
    if (snapshot == null) return map;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final dateStr = data['expiryDate'] ?? '';
      if (dateStr.isEmpty) continue;

      final parsed = DateTime.parse(dateStr);
      final key = DateTime.utc(parsed.year, parsed.month, parsed.day);
      final name = doc['name'] ?? '';

      // 해당 날짜 키가 없으면 빈 리스트 만들고, 음식명 추가
      map.putIfAbsent(key, () => []);
      map[key]!.add(name);
    }
    return map;
  }

  Widget _buildSelectedDayList(Map<DateTime, List<String>> expiryMap) {
    if (_selectedDay == null) {
      return const Center(child: Text('날짜를 선택하면 만료 예정 식품이 표시됩니다'));
    }

    final key = DateTime.utc(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final items = expiryMap[key] ?? [];

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
            subtitle: Text('${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')} 만료'),
          ),
        );
      },
    );
  }
}