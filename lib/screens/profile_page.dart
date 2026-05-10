import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/allergy_options.dart';
import '../theme/app_colors.dart';

/// 사용자 프로필(알레르기/비선호/선호) 편집 페이지
/// AppBar의 person_outline 아이콘으로 모든 메인 페이지에서 진입 가능
class ProfilePage extends StatefulWidget {
  final String userId;
  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 선택된 항목들 (Set 사용 — 중복 방지 + 빠른 조회)
  final Set<String> _selectedAllergies = {};
  final Set<String> _selectedDislikes = {};
  final Set<String> _selectedPreferences = {};

  // 사용자 정의 항목 (체크박스에 없는 것)
  final List<String> _customAllergies = [];
  final List<String> _customDislikes = [];
  final List<String> _customPreferences = [];

  // 직접 입력용 컨트롤러
  final _allergyInputController = TextEditingController();
  final _dislikeInputController = TextEditingController();
  final _preferenceInputController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _allergyInputController.dispose();
    _dislikeInputController.dispose();
    _preferenceInputController.dispose();
    super.dispose();
  }

  /// Firestore에서 기존 프로필을 읽어와 상태에 반영
  /// 미리 정의된 옵션에 있는 값은 _selected*에, 없으면 _custom*에 분류
  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final allergies = (data['allergies'] as List?)?.cast<String>() ?? [];
        final dislikes = (data['dislikes'] as List?)?.cast<String>() ?? [];
        final preferences = (data['preferences'] as List?)?.cast<String>() ?? [];

        for (final item in allergies) {
          if (allergyOptions.contains(item)) {
            _selectedAllergies.add(item);
          } else {
            _customAllergies.add(item);
          }
        }
        for (final item in dislikes) {
          if (dislikeOptions.contains(item)) {
            _selectedDislikes.add(item);
          } else {
            _customDislikes.add(item);
          }
        }
        for (final item in preferences) {
          if (preferenceOptions.contains(item)) {
            _selectedPreferences.add(item);
          } else {
            _customPreferences.add(item);
          }
        }
      }
    } catch (_) {
      // 문서 없거나 읽기 실패 시 기본값 (빈 상태)으로 진행
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Firestore에 저장. set with merge: true 로 user 문서가 없어도 안전
  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final allergies = [..._selectedAllergies, ..._customAllergies];
      final dislikes = [..._selectedDislikes, ..._customDislikes];
      final preferences = [..._selectedPreferences, ..._customPreferences];

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
        'allergies': allergies,
        'dislikes': dislikes,
        'preferences': preferences,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('프로필이 저장되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
      // pop 시 true 전달 → 챗봇 페이지가 재초기화 트리거
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isSaving = false);
    }
  }

  /// 직접 입력 추가 핸들러 — 빈 문자열/중복 방지
  void _addCustomItem(
      TextEditingController controller, List<String> targetList) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (targetList.contains(text)) return; // 중복 방지

    setState(() {
      targetList.add(text);
      controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('내 정보'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                // 색 미지정: AppBar 테마의 foregroundColor를 따라감
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              // 색 미지정: AppBar 테마의 foregroundColor를 따라감
              child: const Text('저장',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    title: '⚠️  알레르기',
                    subtitle: '선택한 식재료는 AI 추천에서 제외됩니다.',
                    options: allergyOptions,
                    selected: _selectedAllergies,
                    customItems: _customAllergies,
                    inputController: _allergyInputController,
                    inputHint: '기타 알레르기 직접 입력',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: '🥦  비선호 식재료',
                    subtitle: '가능하면 제외되며, 대체 재료가 제안됩니다.',
                    options: dislikeOptions,
                    selected: _selectedDislikes,
                    customItems: _customDislikes,
                    inputController: _dislikeInputController,
                    inputHint: '기타 비선호 식재료 직접 입력',
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: '💡  선호도',
                    subtitle: '레시피 추천 시 우선순위로 반영됩니다.',
                    options: preferenceOptions,
                    selected: _selectedPreferences,
                    customItems: _customPreferences,
                    inputController: _preferenceInputController,
                    inputHint: '기타 선호 직접 입력',
                  ),
                  const SizedBox(height: 32),
                  // 면책 문구 — 알레르기는 안전 직결이므로 명시 필요
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppColors.primaryDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '알레르기 정보는 AI 추천에 반영되지만, 실제 섭취 전 식품 라벨을 반드시 확인해주세요.',
                            style: TextStyle(fontSize: 11, color: AppColors.primaryDark, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 한 섹션(알레르기/비선호/선호) 렌더링 — 헤더 + 칩 그리드 + 직접입력 + 사용자정의 칩
  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<String> options,
    required Set<String> selected,
    required List<String> customItems,
    required TextEditingController inputController,
    required String inputHint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: AppColors.warmBrown)),
          const SizedBox(height: 12),

          // 미리 정의된 옵션들 — FilterChip
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return FilterChip(
                label: Text(opt, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      selected.add(opt);
                    } else {
                      selected.remove(opt);
                    }
                  });
                },
                selectedColor: AppColors.primaryPale,
                checkmarkColor: AppColors.primaryDark,
                backgroundColor: AppColors.surface,
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.surfaceDark),
          const SizedBox(height: 12),

          // 직접 입력
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  decoration: InputDecoration(
                    hintText: inputHint,
                    hintStyle: TextStyle(fontSize: 12, color: AppColors.warmBrown),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _addCustomItem(inputController, customItems),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _addCustomItem(inputController, customItems),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('추가', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),

          // 사용자 정의 항목들 (있을 때만)
          if (customItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: customItems.map((item) {
                return Chip(
                  label: Text(item, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => customItems.remove(item)),
                  deleteIconColor: AppColors.warmBrown,
                  backgroundColor: AppColors.primaryPale,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
