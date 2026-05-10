
class ChatMessage {
  // Firestore 문서 ID. 신규 메시지는 add() 후 채워짐.
  // 사용자가 보낸 메시지처럼 차감/폐기와 무관한 경우 null 가능.
  String? id;

  final String role; // "user" or "assistant"
  final String text;
  final String? mealName;
  final List<Map<String, dynamic>>? ingredients;      // 재고 차감용
  final List<Map<String, dynamic>>? recommendations;  // 레시피 추천 카드용
  final Map<String, dynamic>? analysis;               // 냉장고 분석
  final Map<String, dynamic>? nutrition;

  // 액션 수행 여부 — 한 번 누르면 true로 바뀌고 버튼 비활성화
  // mutable: 사용자가 버튼 누른 직후 setState로 갱신하기 위함
  bool isDeducted;
  bool isDiscarded;

  ChatMessage({
    this.id,
    required this.role,
    required this.text,
    this.mealName,
    this.ingredients,
    this.recommendations,
    this.analysis,
    this.nutrition,
    this.isDeducted = false,
    this.isDiscarded = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'text': text,
    };
  }
}