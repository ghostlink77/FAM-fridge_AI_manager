import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_add_selection_page.dart';
import '../widgets/main_bottom_nav.dart';

class InventoryItem {
  final String id;
  final String name;
  final String expiryDate;
  final String registrationDate;
  final num quantity;

  InventoryItem({
    required this.id,
    required this.name,
    required this.expiryDate,
    required this.registrationDate,
    required this.quantity,
  });

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      expiryDate: data['expiryDate'] ?? '',
      registrationDate: data['registrationDate'] ?? '',
      quantity: (data['quantity'] as num?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'expiryDate': expiryDate,
      'registrationDate': registrationDate,
      'quantity': quantity,
    };
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
    List<InventoryItem> sorted = List.from(items);
    
    switch (tabIndex) {
      case 0: // 유통기한 임박순
        sorted.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        break;
      case 1: // 이름순
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 2: // 최근 등록순
        sorted.sort((a, b) => b.registrationDate.compareTo(a.registrationDate));
        break;
    }
    
    return sorted;
  }

  void _showChatbotMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('추후 제공될 예정입니다.'),
        duration: Duration(seconds: 2),
      ),
    );
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
            Tab(text: '유통기한 임박순'),
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
      bottomNavigationBar: MainBottomNav(
        currentIndex: 1,
        userId: widget.userId
      ),
      floatingActionButton: MainBottomNav.buildFAB(context, widget.userId),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  Widget _buildInventoryList(List<InventoryItem> inventoryItems, int tabIndex) {
    // 재고가 없으면 Empty 메시지 표시
    if (inventoryItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 100,
              color: Colors.grey[300],
            ),
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            onLongPress: () => _showDeleteDialog(context, item),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 재고 이름 (크게)
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // 유통기한, 등록일자, 수량 (작게)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '유통기한: ${item.expiryDate}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '수량: ${item.quantity == item.quantity.toInt() ? item.quantity.toInt() : item.quantity}개',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '등록일자: ${item.registrationDate}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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

  Future<void> _showDeleteDialog(BuildContext context, InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('재고 삭제'),
          content: Text('"${item.name}"을(를) 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
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
