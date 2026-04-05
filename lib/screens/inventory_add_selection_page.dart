import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'inventory_add_input_page.dart';
import 'inventory_add_ocr_page.dart';
import 'inventory_add_voice_page.dart';
import '../widgets/main_bottom_nav.dart';

class InventoryAddSelectionPage extends StatefulWidget {
  final String userId;

  const InventoryAddSelectionPage({super.key, required this.userId});

  @override
  State<InventoryAddSelectionPage> createState() =>
      _InventoryAddSelectionPageState();
}

class _InventoryAddSelectionPageState extends State<InventoryAddSelectionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('재고 등록 방법 선택'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 85),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // 직접 입력 버튼
            _buildMethodCard(
              icon: Icons.edit_note,
              title: '직접 입력',
              subtitle: '식품명, 수량, 소비기한을 직접 입력',
              iconColor: const Color(0xFF4CAF50),
              iconBgColor: const Color(0xFF4CAF50).withValues(alpha: 0.12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        InventoryAddInputPage(userId: widget.userId),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // 사진 등록 버튼
            _buildMethodCard(
              icon: Icons.camera_alt,
              title: '사진 등록',
              subtitle: '영수증 사진으로 자동 인식',
              iconColor: const Color(0xFF2196F3),
              iconBgColor: const Color(0xFF2196F3).withValues(alpha: 0.12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        InventoryAddOcrPage(userId: widget.userId),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // 음성 등록 버튼
            _buildMethodCard(
              icon: Icons.mic,
              title: '음성 등록',
              subtitle: '음성으로 등록',
              iconColor: const Color(0xFF9C27B0),
              iconBgColor: const Color(0xFF9C27B0).withValues(alpha: 0.12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        InventoryAddVoicePage(userId: widget.userId),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: MainBottomNav(currentIndex: 1, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceDark),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
