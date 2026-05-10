import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/chat_message.dart';
import '../../theme/app_colors.dart';
import 'recipe_card.dart';
import 'analysis_card.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(String recipeName) onRecipeTap;
  // messageId가 추가됨 — 차감/폐기 후 어느 메시지의 버튼이 눌렸는지 chatbot_page가 식별 가능
  final Function(String? messageId, List<String> expiredItems) onDiscardTap;
  final Function(String? messageId, List<Map<String, dynamic>> ingredients, String? mealName, Map<String, dynamic>? nutrition) onDeductTap;

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
                  messageId: message.id,
                  onDiscardTap: onDiscardTap,
                  isDiscarded: message.isDiscarded),
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
              // 차감 완료 후엔 onPressed: null + 회색 톤 + "차감됨" 라벨
              // (버튼을 숨기지 않고 흔적을 남겨 사용자에게 상태를 명시)
              ElevatedButton.icon(
                onPressed: message.isDeducted
                    ? null
                    : () => onDeductTap(message.id, message.ingredients!, message.mealName, message.nutrition),
                icon: Icon(
                  message.isDeducted ? Icons.check_circle_outline : Icons.remove_shopping_cart,
                  size: 16,
                ),
                label: Text(message.isDeducted ? '차감됨' : '재고 차감'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  // disabled 상태 색 명시 (기본은 너무 흐릿함)
                  disabledBackgroundColor: AppColors.surfaceDark,
                  disabledForegroundColor: AppColors.warmBrown,
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