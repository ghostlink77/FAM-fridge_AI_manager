import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/chat_message.dart';
import '../../theme/app_colors.dart';
import 'recipe_card.dart';
import 'analysis_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(String recipeName) onRecipeTap;
  final Function(List<String> expiredItems) onDiscardTap;
  final Function(List<Map<String, dynamic>> ingredients, String? mealName, Map<String, dynamic>? nutrition) onDeductTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.onRecipeTap,
    required this.onDiscardTap,
    required this.onDeductTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primaryDark : Colors.white,
          border: isUser ? null : Border.all(color: AppColors.surfaceDark),
          borderRadius: isUser
              ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          )
              : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: isUser
            ? Text(
          message.text,
          style: const TextStyle(fontSize: 15, color: Colors.white),
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(data: message.text),
            if (message.analysis != null) ...[
              AnalysisCard(
                  analysis: message.analysis!,
                  onDiscardTap: onDiscardTap),
            ],
            if (message.recommendations != null &&
                message.recommendations!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...message.recommendations!.map((rec) => RecipeCard(
                rec: rec, onRecipeTap: onRecipeTap,
              )),
            ],
            if (message.ingredients != null &&
                message.ingredients!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => onDeductTap(message.ingredients!, message.mealName, message.nutrition),
                icon: const Icon(Icons.remove_shopping_cart, size: 16),
                label: const Text('재고 차감'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}