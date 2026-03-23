/// 途正英语 - 群聊信息页面
/// 火鹰科技出品
///
/// 参考微信群聊详情页：
/// 1. 群成员头像网格（点击查看全部 / +邀请 / -踢出）
/// 2. 群名称（可编辑）
/// 3. 群公告
/// 4. 我的群昵称
/// 5. 消息免打扰
/// 6. 群管理（群主/管理员可见）
/// 7. 退出群聊 / 解散群聊

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../services/team_service.dart';
import '../../services/user_info_service.dart';
import '../../services/im_service.dart';
import '../../services/conversation_service.dart';
import 'select_contacts_page.dart';

class TeamInfoPage extends StatefulWidget {
  final String teamId;
  final String conversationId;

  const TeamInfoPage({
    super.key,
    required this.teamId,
    required this.conversationId,
  });

  @override
  State<TeamInfoPage> createState() => _TeamInfoPageState();
}

class _TeamInfoPageState extends State<TeamInfoPage> {
  NIMTeam? _teamInfo;
  List<NIMTeamMember> _members = [];
  bool _isLoading = true;
  bool _isMuted = false;
  StreamSubscription? _teamUpdatedSub;
  StreamSubscription? _memberChangedSub;

  String get _myAccid => IMService.instance.currentAccid ?? '';

  /// 当前用户是否是群主
  bool get _isOwner => _teamInfo?.ownerAccountId == _myAccid;

  /// 当前用户是否是管理员或群主
  bool get _isManager {
    final myMember = _members.where((m) => m.accountId == _myAccid).firstOrNull;
    if (myMember == null) return false;
    return myMember.memberRole == NIMTeamMemberRole.teamMemberRoleOwner ||
        myMember.memberRole == NIMTeamMemberRole.teamMemberRoleManager;
  }

  @override
  void initState() {
    super.initState();
    _loadTeamInfo();
    _setupListeners();
    _loadMuteStatus();
  }

  @override
  void dispose() {
    _teamUpdatedSub?.cancel();
    _memberChangedSub?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    _teamUpdatedSub = TZTeamService.instance.teamUpdatedStream.listen((team) {
      if (team.teamId == widget.teamId) {
        setState(() => _teamInfo = team);
      }
    });

    _memberChangedSub =
        TZTeamService.instance.memberChangedStream.listen((teamId) {
      if (teamId == widget.teamId) {
        _loadMembers();
      }
    });
  }

  Future<void> _loadTeamInfo() async {
    setState(() => _isLoading = true);

    try {
      final team = await TZTeamService.instance.getTeamInfo(widget.teamId);
      if (team != null && mounted) {
        setState(() => _teamInfo = team);
      }
      await _loadMembers();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMembers() async {
    final members = await TZTeamService.instance.getTeamMembers(widget.teamId);

    // 批量获取用户信息
    final accids = members.map((m) => m.accountId ?? '').where((a) => a.isNotEmpty).toList();
    await UserInfoService.instance.getUserInfoBatch(accids);

    if (mounted) {
      setState(() => _members = members);
    }
  }

  void _loadMuteStatus() {
    final conv = TZConversationService.instance.conversations
        .where((c) => c.conversationId == widget.conversationId)
        .firstOrNull;
    if (conv != null) {
      _isMuted = conv.isMuted;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 操作方法
  // ═══════════════════════════════════════════════════════

  /// 编辑群名称
  void _editTeamName() {
    final controller = TextEditingController(text: _teamInfo?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('修改群名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: '请输入群名称',
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final success =
                  await TZTeamService.instance.updateTeamName(widget.teamId, name);
              if (success && mounted) {
                setState(() {});
                _loadTeamInfo();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose;
  }

  /// 编辑群公告
  void _editAnnouncement() {
    final controller =
        TextEditingController(text: _teamInfo?.announcement ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('修改群公告'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '请输入群公告',
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await TZTeamService.instance
                  .updateTeamAnnouncement(widget.teamId, controller.text.trim());
              if (mounted) _loadTeamInfo();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 编辑我的群昵称
  void _editMyNick() {
    final myMember = _members.where((m) => m.accountId == _myAccid).firstOrNull;
    final controller = TextEditingController(text: myMember?.teamNick ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('我在本群的昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: '请输入群昵称',
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await TZTeamService.instance
                  .updateMyTeamNick(widget.teamId, controller.text.trim());
              if (mounted) _loadMembers();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 邀请新成员
  Future<void> _inviteMembers() async {
    final existingAccids = _members
        .map((m) => m.accountId ?? '')
        .where((a) => a.isNotEmpty)
        .toList();

    final result = await Navigator.of(context).push<List<SelectableContact>>(
      MaterialPageRoute(
        builder: (_) => SelectContactsPage(
          title: '邀请新成员',
          existingMembers: existingAccids,
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final accids = result.map((c) => c.accid).toList();
      final inviteResult =
          await TZTeamService.instance.inviteMembers(widget.teamId, accids);

      if (mounted) {
        if (inviteResult.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已邀请 ${result.length} 人加入群聊'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _loadMembers();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('邀请失败: ${inviteResult.error}'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    }
  }

  /// 踢出成员
  void _showKickMember(NIMTeamMember member) {
    final accid = member.accountId ?? '';
    final userInfo = UserInfoService.instance.getCached(accid);
    final name = member.teamNick ?? userInfo?.name ?? accid;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除群成员'),
        content: Text('确定要将 $name 移出群聊吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await TZTeamService.instance
                  .kickMember(widget.teamId, [accid]);
              if (mounted) {
                if (result.success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已移除'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                  _loadMembers();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('移除失败: ${result.error}'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  /// 退出群聊
  void _confirmLeaveTeam() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出群聊'),
        content: const Text('退出后将不再接收此群聊消息，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result =
                  await TZTeamService.instance.leaveTeam(widget.teamId);
              if (mounted) {
                if (result.success) {
                  // 删除本地会话
                  await TZConversationService.instance
                      .deleteConversation(widget.conversationId);
                  if (mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('退出失败: ${result.error}'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  /// 解散群聊（仅群主）
  void _confirmDismissTeam() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('解散群聊'),
        content: const Text('解散后所有成员将被移出，聊天记录将被清空。此操作不可恢复，确定要解散吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result =
                  await TZTeamService.instance.dismissTeam(widget.teamId);
              if (mounted) {
                if (result.success) {
                  await TZConversationService.instance
                      .deleteConversation(widget.conversationId);
                  if (mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('解散失败: ${result.error}'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('解散'),
          ),
        ],
      ),
    );
  }

  /// 切换免打扰
  Future<void> _toggleMute() async {
    final success = await TZConversationService.instance
        .toggleMute(widget.conversationId);
    if (success && mounted) {
      setState(() => _isMuted = !_isMuted);
    }
  }

  /// 显示成员操作菜单
  void _showMemberActions(NIMTeamMember member) {
    if (!_isManager) return;
    if (member.accountId == _myAccid) return;

    // 群主不能被操作
    if (member.memberRole == NIMTeamMemberRole.teamMemberRoleOwner) return;

    final accid = member.accountId ?? '';
    final userInfo = UserInfoService.instance.getCached(accid);
    final name = member.teamNick ?? userInfo?.name ?? accid;
    final isTargetManager =
        member.memberRole == NIMTeamMemberRole.teamMemberRoleManager;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Divider(height: 1),
              // 设置/取消管理员（仅群主可操作）
              if (_isOwner)
                ListTile(
                  leading: Icon(
                    isTargetManager ? Icons.remove_moderator : Icons.admin_panel_settings,
                    color: const Color(0xFF7C3AED),
                  ),
                  title: Text(isTargetManager ? '取消管理员' : '设为管理员'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await TZTeamService.instance.setManager(
                      widget.teamId,
                      accid,
                      isManager: !isTargetManager,
                    );
                    _loadMembers();
                  },
                ),
              // 转让群主（仅群主可操作）
              if (_isOwner)
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Color(0xFFF59E0B)),
                  title: const Text('转让群主'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmTransferOwner(member);
                  },
                ),
              // 移出群聊
              ListTile(
                leading: const Icon(Icons.person_remove, color: Color(0xFFEF4444)),
                title: const Text('移出群聊'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showKickMember(member);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 确认转让群主
  void _confirmTransferOwner(NIMTeamMember member) {
    final accid = member.accountId ?? '';
    final userInfo = UserInfoService.instance.getCached(accid);
    final name = member.teamNick ?? userInfo?.name ?? accid;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('转让群主'),
        content: Text('确定要将群主转让给 $name 吗？转让后你将变为普通成员。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await TZTeamService.instance
                  .transferOwner(widget.teamId, accid);
              if (mounted) {
                if (result.success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('群主已转让'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                  _loadTeamInfo();
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('确认转让'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════

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
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF7C3AED)),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTeamInfo,
                        color: const Color(0xFF7C3AED),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildMembersGrid(),
                            const SizedBox(height: 16),
                            _buildInfoSection(),
                            const SizedBox(height: 16),
                            _buildSettingsSection(),
                            const SizedBox(height: 24),
                            _buildDangerSection(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
              '群聊信息(${_members.length})',
              textAlign: TextAlign.center,
              style: const TextStyle(
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

  /// 群成员网格（参考微信：头像网格 + 邀请按钮 + 移除按钮）
  Widget _buildMembersGrid() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '群成员 (${_members.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              if (_members.length > 15)
                GestureDetector(
                  onTap: () => _showAllMembers(),
                  child: const Row(
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(fontSize: 13, color: Color(0xFF7C3AED)),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: Color(0xFF7C3AED)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // 显示前 15 个成员
              ..._members.take(15).map((member) => _buildMemberItem(member)),
              // 邀请按钮（所有人可见）
              _buildActionButton(
                icon: Icons.add,
                color: const Color(0xFF10B981),
                onTap: _inviteMembers,
              ),
              // 移除按钮（仅管理员/群主可见）
              if (_isManager)
                _buildActionButton(
                  icon: Icons.remove,
                  color: const Color(0xFFEF4444),
                  onTap: _showRemoveMemberSheet,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 成员头像项
  Widget _buildMemberItem(NIMTeamMember member) {
    final accid = member.accountId ?? '';
    final userInfo = UserInfoService.instance.getCached(accid);
    final name = member.teamNick ?? userInfo?.name ?? accid;
    final avatar = userInfo?.avatar ?? '';
    final isOwner =
        member.memberRole == NIMTeamMemberRole.teamMemberRoleOwner;
    final isManagerRole =
        member.memberRole == NIMTeamMemberRole.teamMemberRoleManager;

    return GestureDetector(
      onLongPress: () => _showMemberActions(member),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                _buildAvatar(avatar, name, 44),
                if (isOwner)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '群主',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (isManagerRole)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '管理',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 操作按钮（+邀请 / -移除）
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: color.withOpacity(0.3), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            const Text('', style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  /// 群信息区
  Widget _buildInfoSection() {
    return Container(
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
        children: [
          // 群名称
          _buildInfoTile(
            icon: Icons.group,
            title: '群名称',
            value: _teamInfo?.name ?? '',
            onTap: _isManager ? _editTeamName : null,
          ),
          const Divider(height: 1, indent: 56),
          // 群公告
          _buildInfoTile(
            icon: Icons.campaign,
            title: '群公告',
            value: _teamInfo?.announcement?.isNotEmpty == true
                ? _teamInfo!.announcement!
                : '暂无公告',
            onTap: _isManager ? _editAnnouncement : null,
          ),
          const Divider(height: 1, indent: 56),
          // 群介绍
          _buildInfoTile(
            icon: Icons.info_outline,
            title: '群介绍',
            value: _teamInfo?.intro?.isNotEmpty == true
                ? _teamInfo!.intro!
                : '暂无介绍',
            onTap: null,
          ),
          const Divider(height: 1, indent: 56),
          // 我的群昵称
          _buildInfoTile(
            icon: Icons.badge,
            title: '我的群昵称',
            value: _getMyTeamNick(),
            onTap: _editMyNick,
          ),
        ],
      ),
    );
  }

  String _getMyTeamNick() {
    final myMember =
        _members.where((m) => m.accountId == _myAccid).firstOrNull;
    return myMember?.teamNick?.isNotEmpty == true
        ? myMember!.teamNick!
        : '未设置';
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF7C3AED)),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
              ),
          ],
        ),
      ),
    );
  }

  /// 设置区
  Widget _buildSettingsSection() {
    return Container(
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
        children: [
          // 消息免打扰
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined,
                    size: 20, color: Color(0xFF7C3AED)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '消息免打扰',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
                Switch(
                  value: _isMuted,
                  onChanged: (_) => _toggleMute(),
                  activeColor: const Color(0xFF7C3AED),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 危险操作区
  Widget _buildDangerSection() {
    return Column(
      children: [
        if (!_isOwner)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _confirmLeaveTeam,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                '退出群聊',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        if (_isOwner) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _confirmDismissTeam,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                '解散群聊',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 头像构建
  Widget _buildAvatar(String url, String name, double size) {
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildDefaultAvatar(name, size),
        ),
      );
    }
    return _buildDefaultAvatar(name, size);
  }

  Widget _buildDefaultAvatar(String name, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }

  /// 显示全部成员
  void _showAllMembers() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '全部成员 (${_members.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _members.length,
                itemBuilder: (_, index) {
                  final member = _members[index];
                  final accid = member.accountId ?? '';
                  final userInfo = UserInfoService.instance.getCached(accid);
                  final name = member.teamNick ?? userInfo?.name ?? accid;
                  final avatar = userInfo?.avatar ?? '';
                  final isOwner = member.memberRole ==
                      NIMTeamMemberRole.teamMemberRoleOwner;
                  final isManagerRole = member.memberRole ==
                      NIMTeamMemberRole.teamMemberRoleManager;

                  return ListTile(
                    leading: _buildAvatar(avatar, name, 40),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwner)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '群主',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isManagerRole)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '管理员',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF7C3AED),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onLongPress: () {
                      Navigator.pop(ctx);
                      _showMemberActions(member);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示移除成员底部弹窗
  void _showRemoveMemberSheet() {
    // 过滤掉自己和群主
    final removableMembers = _members.where((m) {
      if (m.accountId == _myAccid) return false;
      if (m.memberRole == NIMTeamMemberRole.teamMemberRoleOwner) return false;
      // 管理员只能被群主移除
      if (!_isOwner &&
          m.memberRole == NIMTeamMemberRole.teamMemberRoleManager) {
        return false;
      }
      return true;
    }).toList();

    if (removableMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可移除的成员'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择要移除的成员',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: removableMembers.length,
                itemBuilder: (_, index) {
                  final member = removableMembers[index];
                  final accid = member.accountId ?? '';
                  final userInfo = UserInfoService.instance.getCached(accid);
                  final name = member.teamNick ?? userInfo?.name ?? accid;
                  final avatar = userInfo?.avatar ?? '';

                  return ListTile(
                    leading: _buildAvatar(avatar, name, 40),
                    title: Text(name),
                    trailing: const Icon(Icons.remove_circle_outline,
                        color: Color(0xFFEF4444)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showKickMember(member);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
