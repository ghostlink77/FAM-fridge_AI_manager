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
                    onDiscardTap: (items) => _showDiscardDialog(items),
                    onDeductTap: (ingredients, mealName, nutrition){
                      _showDeductionDialog(ingredients, mealName: mealName, nutrition: nutrition);
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

    // 3. 프롬프트 파일 읽기 + 재고 정보 삽입
    final todayStr = '${now.year}년 ${now.month}월 ${now.day}일';

    final promptTemplate = await rootBundle.loadString('assets/chatbot_prompt.txt');
    final prompt = promptTemplate
        .replaceAll('{INVENTORY}', inventoryText)
        .replaceAll('{USERNAME}', widget.userId)
        .replaceAll('{DATE}', todayStr);

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
          role: role,
          text: displayText,
          mealName: mealName,
          ingredients: ingredients,
          nutrition: nutrition,
          recommendations: recommendations,
          analysis: analysis
      ));

      history.add(Content(role == 'assistant' ? 'model' : 'user', [TextPart(text)]));
    }

    _chat = _model!.startChat(history: history);

    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _sendMessage() async {
    final userMessage = _messageController.text.trim();
    if (userMessage.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', text: userMessage));
      _loading = true;
    });
    _saveChatMessage('user', userMessage);

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

      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          text: displayText,
          mealName: mealName,
          nutrition: nutrition,
          ingredients: ingredients,
          recommendations: recommendations,
          analysis: analysis,
        ));
      });
      _saveChatMessage('assistant', reply);
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', text: '오류가 발생했습니다.\n$e'));
      });
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _saveChatMessage(String role, String text) async{
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('chat_messages')
        .add({
      'role': role,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _showDeductionDialog(List<Map<String, dynamic>> ingredients, {String? mealName, Map<String, dynamic>? nutrition}) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => DeductionDialog(ingredients: ingredients),
    );

    if(result != null){
      await _deductInventory(result, mealName: mealName ?? '기타', nutrition: nutrition);
    }
  }

  Future<void> _showDiscardDialog(List<String> expiredItems) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => DiscardDialog(expiredItems: expiredItems),
    );

    if(result != null){
      await _discardItems(result);
    }
  }

  Future<void> _discardItems(List<Map<String, dynamic>> items) async {
    final selectedItems = items.where((e) => e['selected'] == true).toList();
    if (selectedItems.isEmpty) return;

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');
      final snapshot = await inventoryRef.get();

      for (var item in selectedItems) {
        final itemName = item['name'] as String;
        for (var doc in snapshot.docs) {
          if (doc.data()['name'] == itemName) {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('폐기 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deductInventory(List<Map<String, dynamic>> items, {String mealName = '직접 입력', Map<String, dynamic>? nutrition}) async {
    final selectedItems = items.where((e) => e['selected'] == true).toList();
    if (selectedItems.isEmpty) return;

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
              await doc.reference.update({'quantity': newQty});
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재고 차감 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 10) return 'breakfast';
    if (hour >= 11 && hour < 14) return 'lunch';
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
