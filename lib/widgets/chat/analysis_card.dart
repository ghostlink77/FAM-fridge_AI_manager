import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class AnalysisCard extends StatelessWidget {
  final Map<String, dynamic> analysis;
  final Function(List<String> expiredItems) onDiscardTap;

  const AnalysisCard({
    super.key,
    required this.analysis,
    required this.onDiscardTap,
  });

  @override
  Widget build(BuildContext context) {
    final expired = List<String>.from(analysis['expired'] ?? []);
    final expiringSoon = List<String>.from(analysis['expiringSoon'] ?? []);
    final tips = List<String>.from(analysis['tips'] ?? []);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.primaryLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 소비기한 지난 재료
          if (expired.isNotEmpty) ...[
            const Text('⚠️ 소비기한 지남',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 4),
            ...expired.map((e) => Text('  • $e', style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => onDiscardTap(expired),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('폐기 처리'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
          // 7일 이내 만료
          if (expiringSoon.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('⏰ 7일 이내 만료',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.warning)),
            const SizedBox(height: 4),
            ...expiringSoon.map((e) => Text('  • $e', style: const TextStyle(fontSize: 13))),
          ],
          // 분석 팁
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('💡 분석',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 4),
            ...tips.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $e', style: const TextStyle(fontSize: 13)),
            )),
          ],
        ],
      ),
    );
  }
}