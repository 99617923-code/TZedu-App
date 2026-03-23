/// 途正英语 - 创建群聊页面
/// 火鹰科技出品
///
/// 流程：
/// 1. 从选择联系人页面选择成员后进入此页
/// 2. 填写群名称（必填）
/// 3. 点击创建，调用 TZTeamService 创建群组
/// 4. 创建成功后自动跳转到群聊会话

import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/team_service.dart';
import 'select_contacts_page.dart';
import 'chat_room_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CreateTeamPage extends StatefulWidget {
  /// 已选择的联系人列表
  final List<SelectableContact> selectedContacts;

  const CreateTeamPage({super.key, required this.selectedContacts});

  @override
  State<CreateTeamPage> createState() => _CreateTeamPageState();
}

class _CreateTeamPageState extends State<CreateTeamPage> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // 默认群名称：所有成员名称拼接
    final names = widget.selectedContacts.map((c) => c.name).toList();
    if (names.length <= 3) {
      _nameController.text = names.join('、');
    } else {
      _nameController.text = '${names.take(3).join('、')}等${names.length}人';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 创建群聊
  Future<void> _createTeam() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入群名称'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final accids = widget.selectedContacts.map((c) => c.accid).toList();

      final result = await TZTeamService.instance.createTeam(
        name: name,
        inviteeAccids: accids,
      );

      if (!mounted) return;

      if (result.success && result.conversationId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('群聊创建成功'),
            backgroundColor: Color(0xFF10B981),
          ),
        );

        // 返回到聊天列表，并传递创建结果
        Navigator.of(context).popUntil((route) => route.isFirst);

        // 跳转到群聊页面
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(
              conversationId: result.conversationId!,
              conversationName: name,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建失败: ${result.error ?? "未知错误"}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建异常: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGroupNameSection(),
                      const SizedBox(height: 24),
                      _buildMembersSection(),
                    ],
                  ),
                ),
              ),
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
          const Expanded(
            child: Text(
              '创建群聊',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: TZColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// 群名称输入区
  Widget _buildGroupNameSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.group, size: 20, color: Color(0xFF7C3AED)),
              SizedBox(width: 8),
              Text(
                '群名称',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            maxLength: 30,
            decoration: InputDecoration(
              hintText: '请输入群名称',
              hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// 群成员预览区
  Widget _buildMembersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, size: 20, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Text(
                '群成员 (${widget.selectedContacts.length}人)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.selectedContacts.map((contact) {
              return SizedBox(
                width: 60,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMemberAvatar(contact),
                    const SizedBox(height: 4),
                    Text(
                      contact.name,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 成员头像
  Widget _buildMemberAvatar(SelectableContact contact) {
    if (contact.avatar.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: contact.avatar,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildDefaultAvatar(contact),
        ),
      );
    }
    return _buildDefaultAvatar(contact);
  }

  Widget _buildDefaultAvatar(SelectableContact contact) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }

  /// 底部创建按钮
  Widget _buildBottomBar() {
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
            onPressed: _isCreating ? null : _createTeam,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '创建群聊',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}
