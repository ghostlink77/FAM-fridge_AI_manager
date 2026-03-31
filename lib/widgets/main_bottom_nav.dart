import 'package:flutter/material.dart';
import '../screens/calendar_page.dart';
import '../screens/inventory_list_page.dart';
import '../screens/inventory_add_selection_page.dart';
import '../screens/chatbot_page.dart';
import '../theme/app_colors.dart';

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final String userId;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 85,
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: Row(
        children: [
          _buildTab(context, 0, Icons.calendar_month, '캘린더'),
          _buildTab(context, 1, Icons.list, '목록'),
          Expanded(child: Container()),
          _buildTab(context, 2, Icons.chat, '챗봇'),
          _buildTab(context, 3, Icons.bar_chart, '소비패턴'),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, int index, IconData icon, String label){
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.primary : Colors.grey;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(icon, color: color),
            onPressed: () {
              if(currentIndex == index) return;

              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _getPageForIndex(index),
                  ),
              );
            },
          ),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _getPageForIndex(int index){
    switch(index){
      case 0:
        return CalendarPage(userId: userId);
      case 1:
        return InventoryListPage(userId: userId);
      case 2:
        return ChatbotPage(userId: userId);
      case 3:
        return InventoryListPage(userId: userId);
      default:
        return InventoryListPage(userId: userId);
    }
  }

  static Widget buildFAB(BuildContext context, String userId) {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => InventoryAddSelectionPage(userId: userId),
          ),
        );
      },
      shape: const CircleBorder(),
      child: const Icon(Icons.add, color: Colors.white, size: 32),
    );
  }
}