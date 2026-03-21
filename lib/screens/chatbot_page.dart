import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../widgets/main_bottom_nav.dart';

class ChatbotPage extends StatefulWidget {
  final String userId;
  const ChatbotPage({super.key, required this.userId});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class ChatMessage {
  final String role; // "user" or "assistant"
  final String text;
  final List<Map<String, dynamic>>? ingredients;      // 재고 차감용
  final List<Map<String, dynamic>>? recommendations;  // 레시피 추천 카드용
  final Map<String, dynamic>? analysis;               // 냉장고 분석

  ChatMessage({
    required this.role,
    required this.text,
    this.ingredients,
    this.recommendations,
    this.analysis,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'text': text,
    };
  }
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
        backgroundColor: Colors.deepPurple,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
              onPressed: _clearChat,
              tooltip: '새 대화',
              icon: const Icon(Icons.refresh)
          )
        ],
      ),
      body: _isInitializing
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                child: Text(
                  '메시지를 입력해서 대화를 시작해보세요.\n예: 계란, 양파, 햄으로 할 수 있는 요리 추천해줘',
                  textAlign: TextAlign.center,
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('챗봇이 답변 작성 중...'),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
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
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      child: const Text('전송'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      bottomNavigationBar: MainBottomNav(currentIndex: 2, userId: widget.userId),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
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
      final expiryStr = data['expiryDate'] ?? '';

      DateTime? expiryDate;
      try {
        expiryDate = DateTime.parse(expiryStr);
      } catch(_) {}
      final itemText = '$name ${quantity}${unit} (유통기한: $expiryStr)';

      if (expiryDate == null){
        fresh.add(itemText);
      }
      else if (expiryDate.isBefore(today)) {
        expired.add(itemText);
      }
      else if (expiryDate.difference(today).inDays <= 7) {
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
        sections.add('⚠️ 유통기한 지난 재료:\n${expired.join('\n')}');
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
    final promptTemplate = await rootBundle.loadString('assets/chatbot_prompt.txt');
    final prompt = promptTemplate.replaceAll('{INVENTORY}', inventoryText);

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

      if (role == 'assistant') {
        if (text.contains('---INGREDIENTS---')) {
          final parts = text.split('---INGREDIENTS---');
          displayText = parts[0].trim();
          final jsonPart = parts[1].split('---END_INGREDIENTS---')[0].trim();
          try {
            final parsed = jsonDecode(jsonPart) as List;
            ingredients = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
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
          ingredients: ingredients,
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

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? Text(message.text, style: const TextStyle(fontSize: 15))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(data: message.text),
            // 냉장고 분석 카드
            if (message.analysis != null) ...[
              _buildAnalysisCard(message.analysis!),
            ],
            // 레시피 추천 카드
            if (message.recommendations != null && message.recommendations!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...message.recommendations!.map((rec) => _buildRecipeCard(rec)),
            ],
            // 재고 차감 버튼
            if (message.ingredients != null && message.ingredients!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _showDeductionDialog(message.ingredients!),
                icon: const Icon(Icons.remove_shopping_cart, size: 16),
                label: const Text('재고 차감'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeCard(Map<String, dynamic> rec) {
    final name = rec['name'] ?? '';
    final description = rec['description'] ?? '';
    final timeMin = rec['timeMin'];
    final difficulty = rec['difficulty'] ?? '';

    return GestureDetector(
      onTap: () {
        // 카드 탭하면 자동으로 레시피 요청
        _messageController.text = '$name 레시피 알려줘';
        _sendMessage();
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
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
                color: Colors.deepPurple,
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

  Widget _buildAnalysisCard(Map<String, dynamic> analysis) {
    final expired = List<String>.from(analysis['expired'] ?? []);
    final expiringSoon = List<String>.from(analysis['expiringSoon'] ?? []);
    final tips = List<String>.from(analysis['tips'] ?? []);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 유통기한 지난 재료
          if (expired.isNotEmpty) ...[
            const Text('⚠️ 유통기한 지남',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 4),
            ...expired.map((e) => Text('  • $e', style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showDiscardDialog(expired),
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
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 4),
            ...expiringSoon.map((e) => Text('  • $e', style: const TextStyle(fontSize: 13))),
          ],
          // 분석 팁
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('💡 분석',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
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

      // 재고 차감용 재료 JSON 파싱
      if (reply.contains('---INGREDIENTS---')) {
        final parts = reply.split('---INGREDIENTS---');
        displayText = parts[0].trim();
        final jsonPart = parts[1].split('---END_INGREDIENTS---')[0].trim();
        try {
          final parsed = jsonDecode(jsonPart) as List;
          ingredients = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
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

  Future<void> _showDeductionDialog(List<Map<String, dynamic>> ingredients) async {
    final items = ingredients.map((e) => {
      'name': e['name'],
      'quantity': e['quantity'] ?? 1,
      'unit': e['unit'] ?? '개',
      'selected': true,
    }).toList();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('재고 차감'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Row(
                      children: [
                        Checkbox(
                          value: item['selected'] as bool,
                          onChanged: (val) {
                            setDialogState(() {
                              items[index]['selected'] = val ?? false;
                            });
                          },
                          activeColor: Colors.deepPurple,
                        ),
                        Expanded(
                          child: Text('${item['name']}'),
                        ),
                        SizedBox(
                          width: 60,
                          child: TextFormField(
                            initialValue: '${item['quantity']}',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              suffixText: '${item['unit']}',
                              isDense: true,
                            ),
                            onChanged: (val) {
                              items[index]['quantity'] = double.tryParse(val) ?? 1;
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _deductInventory(items);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: const Text('차감하기', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDiscardDialog(List<String> expiredItems) async {
    final items = expiredItems.map((name) => {
      'name': name,
      'selected': true,
    }).toList();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('폐기 처리'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CheckboxListTile(
                      value: item['selected'] as bool,
                      title: Text('${item['name']}'),
                      activeColor: Colors.red,
                      onChanged: (val) {
                        setDialogState(() {
                          items[index]['selected'] = val ?? false;
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _discardItems(items);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('폐기하기', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
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

  Future<void> _deductInventory(List<Map<String, dynamic>> items) async {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('재고가 차감되었습니다.'),
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
}