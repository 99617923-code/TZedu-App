/// 途正英语 - 选择联系人页面
/// 火鹰科技出品
///
/// 用于：
/// 1. 创建群聊时选择成员
/// 2. 邀请新成员加入群聊
///
/// 数据来源：
/// - 已有的 IM 会话列表中的 P2P 联系人
/// - 手机号搜索用户
///
/// 参考微信"发起群聊"的交互：
/// - 顶部搜索框
/// - 已选联系人横向展示
/// - 联系人列表多选
/// - 底部确认按钮

import 'package:flutter/material.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/conversation_service.dart';
import '../../services/user_info_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 可选择的联系人模型
class SelectableContact {
  final String accid;
  final String name;
  final String avatar;
  final String? role;
  bool isSelected;

  SelectableContact({
    required this.accid,
    required this.name,
    this.avatar = '',
    this.role,
    this.isSelected = false,
  });
}

/// 选择联系人页面
class SelectContactsPage extends StatefulWidget {
  /// 页面标题
  final String title;

  /// 已在群中的成员 accid（不可选择）
  final List<String> existingMembers;

  /// 最大可选人数（0 表示不限制）
  final int maxCount;

  const SelectContactsPage({
    super.key,
    this.title = '选择联系人',
    this.existingMembers = const [],
    this.maxCount = 0,
  });

  @override
  State<SelectContactsPage> createState() => _SelectContactsPageState();
}

class _SelectContactsPageState extends State<SelectContactsPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<SelectableContact> _contacts = [];
  final List<SelectableContact> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 从已有会话列表中加载 P2P 联系人
  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    try {
      final convService = TZConversationService.instance;
      final conversations = convService.conversations;

      // 从 P2P 会话中提取联系人
      final p2pConversations = conversations
          .where((c) => c.type == NIMConversationType.p2p)
          .toList();

      // 批量获取用户信息
      final accids = p2pConversations.map((c) => c.targetId).toList();
      await UserInfoService.instance.getUserInfoBatch(accids);

      final contacts = <SelectableContact>[];
      final addedAccids = <String>{};

      for (final conv in p2pConversations) {
        if (addedAccids.contains(conv.targetId)) continue;
        if (widget.existingMembers.contains(conv.targetId)) continue;

        final userInfo = UserInfoService.instance.getCached(conv.targetId);
        contacts.add(SelectableContact(
          accid: conv.targetId,
          name: userInfo?.name ?? conv.name,
          avatar: userInfo?.avatar ?? conv.avatar,
        ));
        addedAccids.add(conv.targetId);
      }

      // 按名称排序
      contacts.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _contacts.clear();
        _contacts.addAll(contacts);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[SelectContacts] 加载联系人异常: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 搜索用户（手机号）
  Future<void> _searchUser(String phone) async {
    if (phone.isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearching = false;
      });
      return;
    }

    // 如果不是手机号格式，在本地联系人中搜索
    if (!RegExp(r'^\d+$').hasMatch(phone)) {
      setState(() {
        _searchQuery = phone;
        _isSearching = false;
      });
      return;
    }

    // 手机号搜索
    if (phone.length == 11 && RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _isSearching = true);

      try {
        final result = await AuthService.instance.searchUserByPhone(phone);
        if (!mounted) return;

        if (result.success && result.user != null) {
          final user = result.user!;
          // 检查是否已在联系人列表或已在群中
          if (!widget.existingMembers.contains(user.accid)) {
            setState(() {
              _searchResults.clear();
              _searchResults.add(SelectableContact(
                accid: user.accid,
                name: user.nickname,
                avatar: user.avatar,
                role: user.roleLabel,
                isSelected: _contacts.any((c) => c.accid == user.accid && c.isSelected),
              ));
              _isSearching = false;
            });
          } else {
            setState(() {
              _searchResults.clear();
              _isSearching = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('该用户已在群中'),
                  backgroundColor: Color(0xFFF59E0B),
                ),
              );
            }
          }
        } else {
          setState(() {
            _searchResults.clear();
            _isSearching = false;
          });
        }
      } catch (e) {
        setState(() => _isSearching = false);
      }
    } else {
      setState(() {
        _searchQuery = phone;
        _isSearching = false;
      });
    }
  }

  /// 获取已选中的联系人
  List<SelectableContact> get _selectedContacts =>
      _contacts.where((c) => c.isSelected).toList();

  /// 获取显示的联系人列表（支持本地搜索）
  List<SelectableContact> get _displayContacts {
    if (_searchQuery.isNotEmpty) {
      return _contacts
          .where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    return _contacts;
  }

  /// 切换选中状态
  void _toggleContact(SelectableContact contact) {
    if (widget.maxCount > 0 &&
        !contact.isSelected &&
        _selectedContacts.length >= widget.maxCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('最多选择 ${widget.maxCount} 人'),
          backgroundColor: const Color(0xFFF59E0B),
        ),
      );
      return;
    }

    setState(() {
      contact.isSelected = !contact.isSelected;
    });
  }

  /// 从搜索结果中添加联系人
  void _addFromSearch(SelectableContact searchContact) {
    // 检查是否已在联系人列表中
    final existing = _contacts.where((c) => c.accid == searchContact.accid).firstOrNull;
    if (existing != null) {
      _toggleContact(existing);
    } else {
      // 添加到联系人列表并选中
      if (widget.maxCount > 0 && _selectedContacts.length >= widget.maxCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('最多选择 ${widget.maxCount} 人'),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
        return;
      }

      setState(() {
        searchContact.isSelected = true;
        _contacts.add(searchContact);
        _searchResults.clear();
        _searchController.clear();
        _searchQuery = '';
      });
    }
  }

  /// 确认选择
  void _confirmSelection() {
    final selected = _selectedContacts;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择一位联系人'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [TZColors.bgStart, TZColors.bgMid, TZColors.bgEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              if (_selectedContacts.isNotEmpty) _buildSelectedBar(),
              if (_searchResults.isNotEmpty) _buildSearchResults(),
              Expanded(child: _buildContactList()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部导航栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            color: TZColors.textDark,
          ),
          Expanded(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: TZColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 48), // 平衡返回按钮的空间
        ],
      ),
    );
  }

  /// 搜索栏
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索联系人或输入手机号',
          hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Color(0xFF9CA3AF)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _searchResults.clear();
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          _searchUser(value.trim());
        },
      ),
    );
  }

  /// 已选联系人横向展示
  Widget _buildSelectedBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedContacts.length,
        itemBuilder: (context, index) {
          final contact = _selectedContacts[index];
          return GestureDetector(
            onTap: () => _toggleContact(contact),
            child: Container(
              width: 56,
              margin: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      _buildContactAvatar(contact, size: 40),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact.name,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 搜索结果列表
  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '搜索结果',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          ..._searchResults.map((contact) => _buildContactTile(
                contact,
                onTap: () => _addFromSearch(contact),
                showCheckbox: false,
              )),
        ],
      ),
    );
  }

  /// 联系人列表
  Widget _buildContactList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
      );
    }

    final contacts = _displayContacts;

    if (contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: Colors.grey.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? '未找到匹配的联系人' : '暂无联系人\n可通过手机号搜索添加',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return _buildContactTile(
          contact,
          onTap: () => _toggleContact(contact),
          showCheckbox: true,
        );
      },
    );
  }

  /// 联系人列表项
  Widget _buildContactTile(
    SelectableContact contact, {
    required VoidCallback onTap,
    bool showCheckbox = true,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (showCheckbox) ...[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: contact.isSelected
                      ? const Color(0xFF7C3AED)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: contact.isSelected
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                ),
                child: contact.isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
            _buildContactAvatar(contact, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name.isNotEmpty ? contact.name : contact.accid,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  if (contact.role != null)
                    Text(
                      contact.role!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
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

  /// 联系人头像
  Widget _buildContactAvatar(SelectableContact contact, {double size = 40}) {
    if (contact.avatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: CachedNetworkImage(
          imageUrl: contact.avatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildDefaultAvatar(contact, size),
        ),
      );
    }
    return _buildDefaultAvatar(contact, size);
  }

  Widget _buildDefaultAvatar(SelectableContact contact, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(
        child: Text(
          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }

  /// 底部确认按钮
  Widget _buildBottomBar() {
    final count = _selectedContacts.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: count > 0 ? _confirmSelection : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
              disabledForegroundColor: const Color(0xFF9CA3AF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              count > 0 ? '确定($count)' : '请选择联系人',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
