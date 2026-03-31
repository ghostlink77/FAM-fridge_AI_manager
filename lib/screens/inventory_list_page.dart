import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/main_bottom_nav.dart';

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
          backgroundColor: Colors.deepPurple,
          automaticallyImplyLeading: false,
          elevation: 0,
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
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: () => _showEditDialog(item),
            onLongPress: () => _showItemActionDialog(item),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '소비기한: ${item.consumeByDate}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '수량: ${item.quantity == item.quantity.toInt() ? item.quantity.toInt() : item.quantity}개',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '등록일자: ${item.registrationDate}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
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

  Future<void> _showDeleteDialog(BuildContext context, InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('재고 삭제'),
          content: const Text('재고에서 상품을 제거하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      await _deleteInventoryItem(item);
    }
  }

  Future<void> _showItemActionDialog(InventoryItem item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('edit'),
              child: const Text('수정'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (action == 'edit') {
      await _showEditDialog(item);
      return;
    }

    if (action == 'delete') {
      await _showDeleteDialog(context, item);
    }
  }

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
            content: Text('재고가 삭제되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
