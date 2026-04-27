
class ChatMessage {
  final String role; // "user" or "assistant"
  final String text;
  final String? mealName;
  final List<Map<String, dynamic>>? ingredients;      // 재고 차감용
  final List<Map<String, dynamic>>? recommendations;  // 레시피 추천 카드용
  final Map<String, dynamic>? analysis;               // 냉장고 분석
  final Map<String, dynamic>? nutrition;

  ChatMessage({
    required this.role,
    required this.text,
    this.mealName,
    this.ingredients,
    this.recommendations,
    this.analysis,
    this.nutrition,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'text': text,
    };
  }
}