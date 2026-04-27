import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class RecipeCard extends StatelessWidget {
  final Map<String, dynamic> rec;
  final Function(String recipeName) onRecipeTap;

  const RecipeCard({
    super.key,
    required this.rec,
    required this.onRecipeTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = rec['name'] ?? '';
    final description = rec['description'] ?? '';
    final timeMin = rec['timeMin'];
    final difficulty = rec['difficulty'] ?? '';

    return GestureDetector(
      onTap: () => onRecipeTap(name),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.primaryLight),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE65100),
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (timeMin != null) ...[
                  Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('$timeMin분', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                ],
                if (difficulty.isNotEmpty) ...[
                  Icon(Icons.signal_cellular_alt, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(difficulty, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}