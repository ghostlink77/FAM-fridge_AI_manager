import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/main_bottom_nav.dart';
import '../theme/app_colors.dart';
import '../utils/freshness_utils.dart';
import 'profile_page.dart';

class InventoryItem {
  final String id;
  final String name;
  final String consumeByDate;
  final List<String> consumeByDates;
  final String registrationDate;
  final num quantity;

  InventoryItem({
    required this.id,
    required this.name,
    required this.consumeByDate,
    required this.consumeByDates,
    required this.registrationDate,
    required this.quantity,
  });

  static List<String> _extractConsumeByDates(
    dynamic consumeByDatesRaw,
    dynamic consumeByDateRaw,
  ) {
    final dates = <String>[];

    if (consumeByDatesRaw is List) {
      for (final date in consumeByDatesRaw) {
        final text = date?.toString().trim();
        if (text != null && DateTime.tryParse(text) != null) {
          dates.add(text);
        }
      }
    }

    final singleDate = consumeByDateRaw?.toString().trim();
    if (singleDate != null && DateTime.tryParse(singleDate) != null) {
      dates.add(singleDate);
    }

    return dates.toSet().toList()..sort();
  }

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final consumeByDates = _extractConsumeByDates(
      data['consumeByDates'],
      data['consumeByDate'],
    );

    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      consumeByDate: consumeByDates.isNotEmpty ? consumeByDates.first : '',
      consumeByDates: consumeByDates,
      registrationDate: data['registrationDate'] ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
    );
  }
}

class InventoryListPage extends StatefulWidget {
  final String userId;

  const InventoryListPage({super.key, required this.userId});

  @override
  State<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends State<InventoryListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isValidDateString(String value) {
    if (value.trim().isEmpty) return false;
    return DateTime.tryParse(value.trim()) != null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<List<InventoryItem>> getInventoryStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('inventory')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => InventoryItem.fromFirestore(doc))
            .toList());
  }

  List<InventoryItem> getSortedItems(List<InventoryItem> items, int tabIndex) {
    final sorted = List<InventoryItem>.from(items);

    switch (tabIndex) {
      case 0:
        sorted.sort((a, b) => a.consumeByDate.compareTo(b.consumeByDate));
        break;
      case 1:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 2:
        sorted.sort((a, b) => b.registrationDate.compareTo(a.registrationDate));
        break;
    }

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.userId}님의 냉장고'),
          automaticallyImplyLeading: false,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: '내 정보',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePage(userId: widget.userId),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '소비기한 임박순'),
              Tab(text: '이름순'),
              Tab(text: '최근 등록순'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: StreamBuilder<List<InventoryItem>>(
          stream: getInventoryStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
            }

            final inventoryItems = snapshot.data ?? [];
            return TabBarView(
              controller: _tabController,
              children: [
                _buildInventoryList(inventoryItems, 0),
                _buildInventoryList(inventoryItems, 1),
                _buildInventoryList(inventoryItems, 2),
              ],
            );
          },
        ),
        bottomNavigationBar: MainBottomNav(currentIndex: 1, userId: widget.userId),
        floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  Widget _buildInventoryList(List<InventoryItem> inventoryItems, int tabIndex) {
    if (inventoryItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Empty',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '등록된 재고가 없습니다',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    final sortedItems = getSortedItems(inventoryItems, tabIndex);

    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 75),
      itemCount: sortedItems.length,
      itemBuilder: (context, index) {
        final item = sortedItems[index];

        final status = getFreshStatus(item.consumeByDate);
        final daysLeft = getDaysLeft(item.consumeByDate);
        final ddayText = getDdayText(item.consumeByDate);
        final statusColor = getStatusColor(status);
        final statusBgColor = getStatusBgColor(status);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: InkWell(
            onTap: () => _showEditDialog(item),
            onLongPress: () => _showItemActionDialog(item),
            borderRadius: BorderRadius.circular(12),
            // ② Container로 감싸서 왼쪽 테두리 구현
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: statusColor, width: 4),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              // ③ Row: D-day 뱃지 + 텍스트 영역
              child: Row(
                children: [
                  // D-day 뱃지
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      ddayText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 텍스트 영역
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 이름 + 수량
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${item.quantity == item.quantity.toInt() ? item.quantity.toInt() : item.quantity}개',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 소비기한 텍스트 (상태별 색상)
                        Text(
                          _buildExpiryText(item.consumeByDate, status, daysLeft),
                          style: TextStyle(
                            fontSize: 12,
                            color: status == FreshStatus.unknown
                                ? AppColors.textSecondary
                                : statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildExpiryText(String consumeByDate, FreshStatus status, int daysLeft){
    if (consumeByDate.isEmpty) return '소비기한 미등록';

    switch (status) {
      case FreshStatus.danger:
        if (daysLeft == 0) return '소비기한 $consumeByDate · 오늘 만료!';
        return '소비기한 $consumeByDate · ${-daysLeft}일 경과';
      case FreshStatus.warning:
        return '소비기한 $consumeByDate · $daysLeft일 남음 ⚠';
      case FreshStatus.fresh:
        return '소비기한 $consumeByDate';
      case FreshStatus.unknown:
        return '소비기한 미등록';
    }
  }

  Future<void> _showEditDialog(InventoryItem item) async {
    final nameController = TextEditingController(text: item.name);
    final quantityController = TextEditingController(text: item.quantity.toString());
    final consumeByDateController = TextEditingController(text: item.consumeByDate);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('재고 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '이름',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '수량',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: consumeByDateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: '소비기한',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final initialDate = _isValidDateString(consumeByDateController.text)
                      ? DateTime.parse(consumeByDateController.text)
                      : DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initialDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    consumeByDateController.text =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final newName = nameController.text.trim();
    final newQuantity = int.tryParse(quantityController.text.trim());
    final newConsumeByDate = consumeByDateController.text.trim();

    if (newName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름을 입력해주세요.')),
        );
      }
      return;
    }

    if (newQuantity == null || newQuantity <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수량은 1 이상 숫자여야 합니다.')),
        );
      }
      return;
    }

    if (!_isValidDateString(newConsumeByDate)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('소비기한 날짜 형식을 확인해주세요.')),
        );
      }
      return;
    }

    await _updateInventoryItem(item.id, newName, newQuantity, newConsumeByDate);
  }

  Future<void> _updateInventoryItem(
    String id,
    String name,
    int quantity,
    String consumeByDate,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory')
          .doc(id)
          .update({
        'name': name,
        'quantity': quantity,
        'consumeByDate': consumeByDate,
        'consumeByDates': [consumeByDate],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('재고가 수정되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('수정 실패: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// "소비" 액션 — 다 먹었거나 잘못 등록한 항목 제거 (폐기 기록 X)
  Future<void> _showConsumeDialog(BuildContext context, InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('재고 소비 처리'),
          content: Text('${item.name}을(를) 다 먹은 것으로 처리하고 재고에서 제거할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('소비 처리'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      await _deleteInventoryItem(item);
    }
  }

  /// "폐기" 액션 — 폐기 기록 남기고 재고에서 제거. 폐기 분석에 반영됨
  Future<void> _showDiscardDialog(BuildContext context, InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('재고 폐기 처리'),
          content: Text(
            '${item.name}을(를) 폐기 처리할까요?\n\n폐기 기록은 소비패턴 분석에 반영됩니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('폐기'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      await _discardInventoryItem(item);
    }
  }

  Future<void> _showItemActionDialog(InventoryItem item) async {
    // AlertDialog의 actions 영역은 한 줄에 가로 배치 — 4개 버튼은 좁아 보일 수 있어
    // content에 ListTile 형태로 두고 actions에는 취소만 두는 패턴이 더 깔끔함
    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item.name),
          // contentPadding으로 ListTile 좌우 여백 확보
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('수정'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.restaurant_outlined, color: Colors.green),
                title: const Text('소비'),
                subtitle: const Text('이미 다 먹었거나 사용했어요'),
                onTap: () => Navigator.of(context).pop('consume'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('폐기'),
                subtitle: const Text('상해서 버려요 (분석에 반영됨)'),
                onTap: () => Navigator.of(context).pop('discard'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );

    if (action == 'edit') {
      await _showEditDialog(item);
      return;
    }

    if (action == 'consume') {
      // 소비: 단순 삭제 (discard_records 기록 없음, 이전과 동일 동작)
      await _showConsumeDialog(context, item);
      return;
    }

    if (action == 'discard') {
      // 폐기: 확인 다이얼로그 → discard_records 기록 + 삭제
      await _showDiscardDialog(context, item);
    }
  }

  /// 소비 처리: 단순 삭제. 폐기 기록 X (사용자가 다 먹었거나 잘못 등록한 케이스)
  Future<void> _deleteInventoryItem(InventoryItem item) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory')
          .doc(item.id)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('소비 처리되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('소비 처리 실패: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 폐기 처리: discard_records에 기록 + inventory에서 삭제
  /// 챗봇의 _discardItems와 동일한 패턴 — 기록 저장 성공 후 삭제 (실패 시 데이터 보존)
  /// reason='manual'로 박아서 챗봇 자동 폐기('expired')와 구분
  Future<void> _discardInventoryItem(InventoryItem item) async {
    try {
      final inventoryDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory')
          .doc(item.id);

      // 1) 원본 문서 데이터를 통째로 읽음 — discard_records에 그대로 복사하기 위함
      final docSnapshot = await inventoryDocRef.get();
      if (!docSnapshot.exists) {
        // 이미 삭제된 항목 (다른 디바이스에서 처리됐을 수 있음)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 처리된 항목입니다.')),
          );
        }
        return;
      }
      final data = docSnapshot.data()!;

      // 2) discard_records에 기록 (원본 필드 + 폐기 메타데이터 2개)
      final record = Map<String, dynamic>.from(data);
      record['discardedAt'] = FieldValue.serverTimestamp();
      record['reason'] = 'manual'; // 챗봇 자동 폐기('expired')와 구분

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('discard_records')
          .add(record);

      // 3) 기록 저장 성공 후에 인벤토리에서 삭제
      await inventoryDocRef.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('폐기 처리되었습니다.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('폐기 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
