import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme/app_colors.dart';
import '../widgets/main_bottom_nav.dart';
import '../models/chat_message.dart';
import '../widgets/chat/recipe_card.dart';
import '../widgets/chat/analysis_card.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/deduction_dialog.dart';
import '../widgets/chat/discard_dialog.dart';
import 'profile_page.dart';
import '../constants/nutrition_db.dart';

class ChatbotPage extends StatefulWidget {
  final String userId;
  const ChatbotPage({super.key, required this.userId});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = []; // {role, text}

  GenerativeModel? _model;
  ChatSession? _chat;
  bool _loading = false;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initChatbot();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('레시피 챗봇'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '내 정보',
            onPressed: () async {
              // ProfilePage가 저장 시 true를 pop으로 돌려줌
              // → 새 프로필 반영을 위해 챗봇 즉시 재초기화
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePage(userId: widget.userId),
                ),
              );
              if (updated == true && mounted) {
                setState(() {
                  _isInitializing = true;
                  _messages.clear();
                });
                await _initChatbot();
              }
            },
          ),
        ],
      ),
      body: _isInitializing
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            Expanded(
              child: _messages.isEmpty ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant_menu, size: 64, color: AppColors.primaryLight),
                    const SizedBox(height: 16),
                    Text(
                      '레시피 챗봇에게 물어보세요!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '예: 지금 내가 가진 재료로 할 수 있는 요리 추천해줘',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return MessageBubble(
                    message: message,
                    onRecipeTap: (name) {
                      _messageController.text = '$name 레시피 알려줘';
                      _sendMessage();
                    },
                    // messageId가 추가된 시그니처 — 다이얼로그 핸들러로 그대로 전달
                    onDiscardTap: (messageId, items) => _showDiscardDialog(messageId, items),
                    onDeductTap: (messageId, ingredients, mealName, nutrition) {
                      _showDeductionDialog(messageId, ingredients, mealName: mealName, nutrition: nutrition);
                    },
                  );
                },
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('챗봇이 답변 작성 중...'),
              ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
                color: AppColors.background,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 3,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: '메시지를 입력하세요',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.surfaceDark),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.surfaceDark),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: AppColors.primary),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _loading ? null : _sendMessage,
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      bottomNavigationBar: MainBottomNav(currentIndex: 2, userId: widget.userId),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_new_chat',
        onPressed: _confirmClearChat,
        backgroundColor: AppColors.primaryDark,
        shape: const CircleBorder(),
        child: const Icon(Icons.edit, color: Colors.white, size: 24),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Future<void> _initChatbot() async {
    // 1. Firestore에서 사용자의 재고 읽어오기
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('inventory')
        .get();

    // 2. 재고 목록을 텍스트로 변환
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<String> expired = [];
    List<String> expiringSoon = [];
    List<String> fresh = [];

    for(var doc in snapshot.docs){
      final data = doc.data();
      final name = data['name'] ?? '알 수 없음';
      final quantity = data['quantity'] ?? 1;
      final unit = data['unit'] ?? '개';
      final expiryStr = data['consumeByDate'] ?? data['expiryDate'] ?? '';

      DateTime? consumeByDate;
      try {
        consumeByDate = DateTime.parse(expiryStr);
      } catch(_) {}
      final itemText = '$name ${quantity}${unit} (소비기한: $expiryStr)';

      if (consumeByDate == null){
        fresh.add(itemText);
      }
      else if (consumeByDate.isBefore(today)) {
        expired.add(itemText);
      }
      else if (consumeByDate.difference(today).inDays <= 7) {
        expiringSoon.add(itemText);
      }
      else {
        fresh.add(itemText);
      }
    }

    String inventoryText = '현재 사용자의 냉장고는 비어있습니다.';
    if (snapshot.docs.isNotEmpty) {
      final sections = <String>[];
      if (expired.isNotEmpty){
        sections.add('⚠️ 소비기한 지난 재료:\n${expired.join('\n')}');
      }
      if (expiringSoon.isNotEmpty){
        sections.add('⏰ 7일 이내 만료 예정:\n${expiringSoon.join('\n')}');
      }
      if (fresh.isNotEmpty){
        sections.add('✅ 여유 있는 재료:\n${fresh.join('\n')}');
      }
      inventoryText = '현재 사용자의 냉장고에 있는 재료:\n${sections.join('\n\n')}';
    }

    // 3. 사용자 프로필(알레르기/비선호/선호) 로드
    //    Firestore users/{uid} 문서에서 직접 읽음. 문서 없거나 필드 없으면 '없음'으로 처리.
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final profileData = userDoc.data();
    final allergiesList = (profileData?['allergies'] as List?)?.cast<String>() ?? [];
    final dislikesList = (profileData?['dislikes'] as List?)?.cast<String>() ?? [];
    final preferencesList = (profileData?['preferences'] as List?)?.cast<String>() ?? [];
    final allergiesStr = allergiesList.isEmpty ? '없음' : allergiesList.join(', ');
    final dislikesStr = dislikesList.isEmpty ? '없음' : dislikesList.join(', ');
    final preferencesStr = preferencesList.isEmpty ? '없음' : preferencesList.join(', ');

    // 4. 프롬프트 파일 읽기 + 재고/프로필 정보 삽입
    final todayStr = '${now.year}년 ${now.month}월 ${now.day}일';

    final promptTemplate = await rootBundle.loadString('assets/chatbot_prompt.txt');
    final prompt = promptTemplate
        .replaceAll('{INVENTORY}', inventoryText)
        .replaceAll('{DATE}', todayStr)
        .replaceAll('{ALLERGIES}', allergiesStr)
        .replaceAll('{DISLIKES}', dislikesStr)
        .replaceAll('{PREFERENCES}', preferencesStr)
        // username: 시연용 팀장 이름('승겸님')으로 하드코딩.
        // 프롬프트 작성자가 어떤 변형을 써도 잡히도록 4가지 형태 모두 치환.
        .replaceAll('{username}', '승겸님')
        .replaceAll('{USERNAME}', '승겸님')
        .replaceAll('{user}', '승겸님')
        .replaceAll('{USER}', '승겸님')
        // 영양 추정용 100개 식재료 참조표 (식약처 기반)
        .replaceAll('{NUTRITION_DB}', buildNutritionDbContext());

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      systemInstruction: Content.text(prompt),
    );

    // 4. 저장된 대화 불러오기
    final chatSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('chat_messages')
        .orderBy('createdAt')
        .get();
    final List<Content> history = [];
    for (var doc in chatSnapshot.docs) {
      final data = doc.data();
      final role = data['role'] ?? 'user';
      final text = data['text'] ?? '';
      // 저장된 응답에서 재료/추천 JSON 파싱
      String displayText = text;
      List<Map<String, dynamic>>? ingredients;
      List<Map<String, dynamic>>? recommendations;
      Map<String, dynamic>? analysis;
      String? mealName;
      Map<String, dynamic>? nutrition;

      if (role == 'assistant') {
        if (text.contains('---INGREDIENTS---')) {
          final parts = text.split('---INGREDIENTS---');
          displayText = parts[0].trim();
          final jsonPart = parts[1].split('---END_INGREDIENTS---')[0].trim();
          try {
            final parsed = jsonDecode(jsonPart);
            if (parsed is Map<String, dynamic>) {
              // 새 형식: {"mealName":"...", "items":[...]}
              mealName = parsed['mealName'] as String?;
              final items = parsed['items'] as List;
              ingredients = items.map((e) => Map<String, dynamic>.from(e)).toList();
            } else if (parsed is List) {
              // 이전 형식 호환: [{"name":"...", ...}]
              ingredients = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
            }
          } catch (_) {}
        }
        if (text.contains('---NUTRITION---')) {
          final nParts = text.split('---NUTRITION---');
          final jsonPart = nParts[1].split('---END_NUTRITION---')[0].trim();
          try {
            nutrition = Map<String, dynamic>.from(jsonDecode(jsonPart));
          } catch (_) {}
        }
        if (displayText.contains('---RECOMMENDATIONS---')) {
          final parts = displayText.split('---RECOMMENDATIONS---');
          displayText = parts[0].trim();
          final jsonPart = parts[1].split('---END_RECOMMENDATIONS---')[0].trim();
          try {
            final parsed = jsonDecode(jsonPart) as List;
            recommendations = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
          } catch (_) {}
        }
        if (displayText.contains('---ANALYSIS---')) {
          final parts = displayText.split('---ANALYSIS---');
          displayText = parts[0].trim();
          final jsonPart = parts[1].split('---END_ANALYSIS---')[0].trim();
          try {
            analysis = Map<String, dynamic>.from(jsonDecode(jsonPart));
          } catch (_) {}
        }
      }

      _messages.add(ChatMessage(
          id: doc.id,
          role: role,
          text: displayText,
          mealName: mealName,
          ingredients: ingredients,
          nutrition: nutrition,
          recommendations: recommendations,
          analysis: analysis,
          // 기존 문서에 필드 없을 수 있음(이전 데이터 호환). null이면 false 처리.
          isDeducted: data['isDeducted'] == true,
          isDiscarded: data['isDiscarded'] == true,
      ));

      history.add(Content(role == 'assistant' ? 'model' : 'user', [TextPart(text)]));
    }

    _chat = _model!.startChat(history: history);

    setState(() {
      _isInitializing = false;
    });

    // ListView가 빌드된 후에 스크롤 컨트롤러가 attached됨
    // → setState 끝나고 한 프레임 더 기다린 다음 맨 아래로 점프
    // (애니메이션 없이 즉시 이동: 진입 시 위→아래 스르륵 흐르는 게 어색함)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  Future<void> _sendMessage() async {
    final userMessage = _messageController.text.trim();
    if (userMessage.isEmpty || _loading) return;

    final userMsg = ChatMessage(role: 'user', text: userMessage);
    setState(() {
      _messages.add(userMsg);
      _loading = true;
    });
    // 저장 후 받은 doc id를 메시지에 세팅 (사용자 메시지는 차감/폐기 없지만 일관성 유지)
    _saveChatMessage('user', userMessage).then((id) => userMsg.id = id);

    _messageController.clear();
    _scrollToBottom();

    try {
      // ChatSession이 히스토리를 자동 관리해줌
      final response = await _chat!.sendMessage(Content.text(userMessage));
      final reply = response.text ?? '응답이 비어 있습니다.';

      String displayText = reply;
      List<Map<String, dynamic>>? ingredients;
      List<Map<String, dynamic>>? recommendations;
      String? mealName;
      Map<String, dynamic>? nutrition;

      // 재고 차감용 재료 JSON 파싱
      if (reply.contains('---INGREDIENTS---')) {
        final parts = reply.split('---INGREDIENTS---');
        displayText = parts[0].trim();
        final jsonPart = parts[1].split('---END_INGREDIENTS---')[0].trim();
        try {
          final parsed = jsonDecode(jsonPart);
          if (parsed is Map<String, dynamic>) {
            mealName = parsed['mealName'] as String?;
            final items = parsed['items'] as List;
            ingredients = items.map((e) => Map<String, dynamic>.from(e)).toList();
          } else if (parsed is List) {
            ingredients = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
          }
        } catch (_) {}
      }
      if (reply.contains('---NUTRITION---')) {
        final nParts = reply.split('---NUTRITION---');
        final jsonPart = nParts[1].split('---END_NUTRITION---')[0].trim();
        try {
          nutrition = Map<String, dynamic>.from(jsonDecode(jsonPart));
        } catch (_) {}
      }
      // 레시피 추천 카드 JSON 파싱
      if (displayText.contains('---RECOMMENDATIONS---')) {
        final parts = displayText.split('---RECOMMENDATIONS---');
        displayText = parts[0].trim();
        final jsonPart = parts[1].split('---END_RECOMMENDATIONS---')[0].trim();
        try {
          final parsed = jsonDecode(jsonPart) as List;
          recommendations = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }

      // 냉장고 분석 JSON 파싱
      Map<String, dynamic>? analysis;
      if (displayText.contains('---ANALYSIS---')) {
        final parts = displayText.split('---ANALYSIS---');
        displayText = parts[0].trim();
        final jsonPart = parts[1].split('---END_ANALYSIS---')[0].trim();
        try {
          analysis = Map<String, dynamic>.from(jsonDecode(jsonPart));
        } catch (_) {}
      }

      // 어시스턴트 메시지: 저장 → doc id 받기 → ChatMessage에 id 세팅 → setState로 추가
      // 순서가 중요: id 없는 상태로 화면에 그려졌다가 id 박히면 buton 콜백이 id로 메시지를 못 찾을 수 있음
      final assistantId = await _saveChatMessage('assistant', reply);
      setState(() {
        _messages.add(ChatMessage(
          id: assistantId,
          role: 'assistant',
          text: displayText,
          mealName: mealName,
          nutrition: nutrition,
          ingredients: ingredients,
          recommendations: recommendations,
          analysis: analysis,
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', text: '오류가 발생했습니다.\n$e'));
      });
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  /// 메시지 저장. 호출 측에서 반환된 doc id를 ChatMessage.id에 세팅하면
  /// 추후 차감/폐기 시 같은 문서를 update 할 수 있다.
  Future<String> _saveChatMessage(String role, String text) async {
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('chat_messages')
        .add({
      'role': role,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      // 새 메시지는 항상 false로 시작
      'isDeducted': false,
      'isDiscarded': false,
    });
    return docRef.id;
  }

  Future<void> _showDeductionDialog(String? messageId, List<Map<String, dynamic>> ingredients, {String? mealName, Map<String, dynamic>? nutrition}) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => DeductionDialog(ingredients: ingredients),
    );

    if(result != null){
      // _deductInventory 가 실제 차감 성공 여부를 bool로 반환 → 성공일 때만 메시지 플래그 갱신
      final ok = await _deductInventory(result, mealName: mealName ?? '기타', nutrition: nutrition);
      if (ok && messageId != null) {
        await _markMessageActionDone(messageId, field: 'isDeducted');
      }
    }
  }

  Future<void> _showDiscardDialog(String? messageId, List<String> expiredItems) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => DiscardDialog(expiredItems: expiredItems),
    );

    if(result != null){
      final ok = await _discardItems(result);
      if (ok && messageId != null) {
        await _markMessageActionDone(messageId, field: 'isDiscarded');
      }
    }
  }

  /// 메시지의 액션 플래그(isDeducted/isDiscarded)를 true로 마킹.
  /// - 메모리상의 ChatMessage 객체 갱신 (즉시 UI 반영)
  /// - Firestore 문서도 update (앱 재진입 시에도 유지)
  Future<void> _markMessageActionDone(String messageId, {required String field}) async {
    // 1) 메모리 갱신 — 같은 id의 메시지 찾아 플래그 true로
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      setState(() {
        if (field == 'isDeducted') _messages[idx].isDeducted = true;
        if (field == 'isDiscarded') _messages[idx].isDiscarded = true;
      });
    }
    // 2) Firestore 갱신 — 실패해도 메모리 상태는 유지 (다음 진입 시 재시도되지 않으니 미세한 손실 가능하나 발표 범위 OK)
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('chat_messages')
          .doc(messageId)
          .update({field: true});
    } catch (_) {}
  }

  /// 반환값: 폐기가 실제로 진행됐으면 true, 사용자가 아무것도 선택 안 했거나 에러나면 false
  Future<bool> _discardItems(List<Map<String, dynamic>> items) async {
    final selectedItems = items.where((e) => e['selected'] == true).toList();
    if (selectedItems.isEmpty) return false;

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');
      final discardRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('discard_records');
      final snapshot = await inventoryRef.get();

      for (var item in selectedItems) {
        final itemName = item['name'] as String;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['name'] == itemName) {
            // 1) 폐기 기록 저장: inventory 원본 필드 전부 복사 + 폐기 메타데이터 2개 추가
            final record = Map<String, dynamic>.from(data);
            record['discardedAt'] = FieldValue.serverTimestamp();
            record['reason'] = 'expired';
            await discardRef.add(record);

            // 2) 기록 저장이 성공해야 인벤토리에서 삭제 (실패 시 catch로 빠져 데이터 보존)
            await doc.reference.delete();
            break;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('폐기 처리되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('폐기 실패: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  /// 반환값: 차감이 실제로 진행됐으면 true, 사용자가 아무것도 선택 안 했거나 에러나면 false
  Future<bool> _deductInventory(List<Map<String, dynamic>> items, {String mealName = '직접 입력', Map<String, dynamic>? nutrition}) async {
    final selectedItems = items.where((e) => e['selected'] == true).toList();
    if (selectedItems.isEmpty) return false;

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');

      final snapshot = await inventoryRef.get();

      for (var item in selectedItems) {
        final itemName = item['name'] as String;
        final usedQty = (item['quantity'] as num).toDouble();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['name'] == itemName) {
            final currentQty = (data['quantity'] as num?)?.toDouble() ?? 0;
            final newQty = currentQty - usedQty;

            if (newQty <= 0) {
              await doc.reference.delete();
            } else {
              // confirmed: true — 챗봇으로 차감했다는 건 사용자가 인지한 것이므로
              // 인벤토리 리스트의 NEW 뱃지도 같이 떼어냄. (delete 케이스는 문서 자체 삭제로 자연 해제)
              await doc.reference.update({
                'quantity': newQty,
                'confirmed': true,
              });
            }
            break;
          }
        }
      }

      // 식사 기록 저장
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('meal_records')
          .add({
        'mealName': mealName,
        'ingredients': selectedItems.map((e) => {
          'name': e['name'],
          'quantity': e['quantity'],
          'unit': e['unit'] ?? '개',
        }).toList(),
        'mealTime': FieldValue.serverTimestamp(),
        'mealType': _getMealType(),
        'nutrition': nutrition,
        'source': 'chatbot',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재고가 차감되었습니다. 식사 기록: $mealName (${_getMealType()})'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재고 차감 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  String _getMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 10) return 'breakfast';
    if (hour >= 11 && hour < 17) return 'lunch';
    if (hour >= 17 && hour < 21) return 'dinner';
    return 'snack';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearChat() async {
    final chatRecf = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('chat_messages');
    final docs = await chatRecf.get();
    for(var docs in docs.docs) {
      await docs.reference.delete();
    }

    setState(() {
      _messages.clear();
      _chat = _model!.startChat();
    });
  }

  Future<void> _confirmClearChat() async {
    // 대화가 비어있으면 바로 리턴
    if (_messages.isEmpty) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('새 대화'),
          content: const Text('기존 대화를 초기화하고\n새 대화를 시작하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('새 대화 시작'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _clearChat();
    }
  }
}
