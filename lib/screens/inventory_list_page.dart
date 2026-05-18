import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show routeObserver;
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
  // 라즈베리파이 웹캠 자동 등록 아이템의 NEW 뱃지 판별용
  // - source: 등록 경로 ('manual' | 'ocr' | 'voice' | 'webcam' | '')
  // - confirmed: 사용자가 확인했는지 (webcam에서 자동 등록된 직후엔 false)
  final String source;
  final bool confirmed;

  InventoryItem({
    required this.id,
    required this.name,
    required this.consumeByDate,
    required this.consumeByDates,
    required this.registrationDate,
    required this.quantity,
    this.source = '',
    this.confirmed = true,
  });

  /// 웹캠에서 자동 등록됐고 사용자가 아직 확인하지 않은 아이템
  bool get isNewFromCamera => source == 'webcam' && !confirmed;

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
      // confirmed 필드가 없으면 false로 처리 — 라즈베리파이는 source만 박으면 NEW 동작.
      // source != 'webcam'인 데이터(manual/ocr/voice/기존)는 isNewFromCamera에서
      // source 체크에 걸려 어차피 NEW 안 뜨므로 안전.
      source: (data['source'] as String?) ?? '',
      confirmed: (data['confirmed'] as bool?) ?? false,
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
    with SingleTickerProviderStateMixin, RouteAware {
  late TabController _tabController;

  // 자동 NEW 해제 시스템
  // - 사용자가 목록 페이지에 머무는 동안은 NEW 유지 (의도된 동작).
  // - 다른 페이지로 이동(탭 전환, FAB push, 프로필 push 등)할 때만 NEW를 떼어냄.
  // - RouteAware의 didPushNext에서 처리 — 페이지 전환 이벤트를 정확히 감지.
  // - _pendingNewItemIds: 현재 NEW 상태인 아이템 ID 목록 (build 시 매번 갱신).
  Set<String> _pendingNewItemIds = {};

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RouteObserver에 자기 자신을 등록 → 페이지 라우트 이벤트 콜백을 받기 시작.
    // ModalRoute.of(context)는 didChangeDependencies에서만 안전하게 호출 가능 (initState에선 불가).
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // RouteObserver 구독 해제 (메모리 누수 방지) + 마지막 fallback으로 NEW 처리.
    routeObserver.unsubscribe(this);
    if (_pendingNewItemIds.isNotEmpty) {
      _autoConfirmNewItems(_pendingNewItemIds);
    }
    _tabController.dispose();
    super.dispose();
  }

  /// 다른 라우트가 push되어 이 페이지가 화면에서 가려지는 순간 호출됨.
  /// - 탭 전환(pushReplacement) / FAB로 등록 페이지(push) / 프로필 push 등 모두 잡힘.
  /// - 풀 편집 다이얼로그는 PageRoute가 아니라서(showDialog는 dialog route) 잡히지 않음 → NEW 유지.
  @override
  void didPushNext() {
    if (_pendingNewItemIds.isNotEmpty) {
      _autoConfirmNewItems(_pendingNewItemIds);
    }
    super.didPushNext();
  }

  /// NEW 아이템(웹캠 등록 + 미확인)을 일괄로 confirmed=true 처리.
  /// build 중이나 dispose 후 호출되어도 안전하도록 mounted/setState 호출 없음 (Firestore write만).
  Future<void> _autoConfirmNewItems(Set<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final inventoryRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory');
      for (final id in ids) {
        batch.update(inventoryRef.doc(id), {'confirmed': true});
      }
      await batch.commit();
    } catch (_) {
      // dispose 시점이나 화면 갱신 도중 호출될 수 있음 → 조용히 무시
      // (다음 페이지 진입 시 다시 시도되므로 결국 처리됨)
    }
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
    // 웹캠 자동 등록 + 미확인 아이템은 어느 탭에서든 최상단에 고정.
    // (등록일 내림차순 — 같은 날 여러 개면 임의 순서)
    final newItems = items.where((it) => it.isNewFromCamera).toList()
      ..sort((a, b) => b.registrationDate.compareTo(a.registrationDate));
    final normalItems = items.where((it) => !it.isNewFromCamera).toList();

    switch (tabIndex) {
      case 0:
        normalItems.sort((a, b) => a.consumeByDate.compareTo(b.consumeByDate));
        break;
      case 1:
        normalItems.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 2:
        normalItems.sort((a, b) => b.registrationDate.compareTo(a.registrationDate));
        break;
    }

    return [...newItems, ...normalItems];
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
            // 디버그 빌드에서만 표시 — release 빌드(`flutter build apk --release`)에서는 자동으로 사라짐.
            // 라즈베리파이 없이 NEW 뱃지 동작을 테스트하기 위한 시뮬레이션 버튼.
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.bug_report),
                tooltip: '[DEBUG] 웹캠 등록 시뮬레이션',
                onPressed: _debugAddWebcamItem,
              ),
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

            // 매 stream 업데이트마다 현재 NEW 아이템 ID 갱신.
            // - 라즈베리파이가 페이지 머무는 중에 새로 등록해도 자동 추적됨.
            // - 페이지 떠날 때(didPushNext) 이 Set 기준으로 일괄 confirm 처리.
            _pendingNewItemIds = inventoryItems
                .where((it) => it.isNewFromCamera)
                .map((it) => it.id)
                .toSet();

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
              // NEW 아이템은 주황색 테두리로 강조 (시각 구분)
              color: item.isNewFromCamera
                  ? Colors.orange
                  : statusColor.withValues(alpha: 0.3),
              width: item.isNewFromCamera ? 1.5 : 0.5,
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
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // 웹캠으로 자동 등록된 미확인 아이템엔 [NEW] 뱃지
                                  if (item.isNewFromCamera) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
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
        // 사용자가 풀 편집 다이얼로그에서 저장 = 확인 완료 → NEW 뱃지 제거
        // (일반 아이템엔 영향 없음, 멱등)
        'confirmed': true,
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

  /// [DEBUG ONLY] 라즈베리파이 웹캠 등록을 시뮬레이션.
  /// AppBar의 bug 아이콘 탭 시 호출. release 빌드에서는 버튼이 렌더링되지 않으므로
  /// 이 메서드도 호출 경로가 없어 dead code로 처리됨 (안전).
  /// confirmed 필드는 일부러 박지 않음 — 실제 라즈베리파이도 source만 박을 예정이고
  /// fromFirestore의 디폴트(false)로 처리되는 흐름을 그대로 검증하기 위함.
  Future<void> _debugAddWebcamItem() async {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('inventory')
          .add({
        'name': '테스트우유',
        'quantity': 1,
        'consumeByDate': '',
        'consumeByDates': <String>[],
        'registrationDate': dateStr,
        'source': 'webcam',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('[DEBUG] 웹캠 등록 시뮬레이션 — 테스트우유 추가됨'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('[DEBUG] 시뮬레이션 실패: $e'),
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
