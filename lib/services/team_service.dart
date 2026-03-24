/// 途正英语 - 群组服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. 创建群组（高级群 typeNormal）
/// 2. 获取群组信息、群成员列表
/// 3. 邀请/踢出群成员
/// 4. 修改群名称、群公告、群头像
/// 5. 转让群主、解散群组、退出群组
/// 6. 群禁言管理
/// 7. 修改群昵称
///
/// 安全机制：
/// - 所有 NIM SDK 调用前都检查 IM 初始化和登录状态
/// - 防止 SDK 未初始化时原生层 abort() 导致闪退

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'im_service.dart';
import 'conversation_service.dart';

/// 群组服务（单例）
class TZTeamService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final TZTeamService _instance = TZTeamService._internal();
  static TZTeamService get instance => _instance;
  TZTeamService._internal();

  // ═══════════════════════════════════════════════════════
  // 安全检查
  // ═══════════════════════════════════════════════════════

  bool get _isIMReady =>
      IMService.instance.isInitialized && IMService.instance.isLoggedIn;

  String get _myAccid => IMService.instance.currentAccid ?? '';

  // ═══════════════════════════════════════════════════════
  // 事件流监听
  // ═══════════════════════════════════════════════════════

  StreamSubscription? _teamCreatedSub;
  StreamSubscription? _teamDismissedSub;
  StreamSubscription? _teamInfoUpdatedSub;
  StreamSubscription? _teamMemberJoinedSub;
  StreamSubscription? _teamMemberLeftSub;
  StreamSubscription? _teamMemberKickedSub;

  /// 群组信息变化流（供 UI 监听刷新）
  final StreamController<NIMTeam> _teamUpdatedController =
      StreamController<NIMTeam>.broadcast();
  Stream<NIMTeam> get teamUpdatedStream => _teamUpdatedController.stream;

  /// 群成员变化流
  final StreamController<String> _memberChangedController =
      StreamController<String>.broadcast();
  Stream<String> get memberChangedStream => _memberChangedController.stream;

  /// 初始化监听
  void setupListeners() {
    if (!_isIMReady) return;

    final teamService = NimCore.instance.teamService;

    _teamCreatedSub ??= teamService.onTeamCreated.listen((team) {
      _log('群组创建: ${team.teamId} ${team.name}');
    });

    _teamDismissedSub ??= teamService.onTeamDismissed.listen((team) {
      _log('群组解散: ${team.teamId}');
    });

    _teamInfoUpdatedSub ??= teamService.onTeamInfoUpdated.listen((team) {
      _log('群组信息更新: ${team.teamId} ${team.name}');
      _teamUpdatedController.add(team);
    });

    _teamMemberJoinedSub ??= teamService.onTeamMemberJoined.listen((members) {
      _log('群成员加入: ${members.length} 人');
      if (members.isNotEmpty) {
        _memberChangedController.add(members.first.teamId ?? '');
      }
    });

    _teamMemberLeftSub ??= teamService.onTeamMemberLeft.listen((members) {
      _log('群成员退出: ${members.length} 人');
      if (members.isNotEmpty) {
        _memberChangedController.add(members.first.teamId ?? '');
      }
    });

    _teamMemberKickedSub ??=
        teamService.onTeamMemberKicked.listen((result) {
      _log('群成员被踢');
    });

    _log('群组事件监听注册成功');
  }

  // ═══════════════════════════════════════════════════════
  // 创建群组
  // ═══════════════════════════════════════════════════════

  /// 创建群组
  /// [name] 群名称
  /// [inviteeAccids] 邀请的成员 accid 列表（不包含自己）
  /// [avatar] 群头像 URL（可选）
  /// [intro] 群介绍（可选）
  /// 返回创建结果（包含 teamId 和群信息）
  Future<({bool success, String? teamId, String? conversationId, String? error})>
      createTeam({
    required String name,
    required List<String> inviteeAccids,
    String? avatar,
    String? intro,
  }) async {
    if (!_isIMReady) {
      return (success: false, teamId: null, conversationId: null, error: 'IM 未就绪');
    }

    try {
      _log('创建群组: $name, 邀请 ${inviteeAccids.length} 人');

      final params = NIMCreateTeamParams(
        name: name,
        teamType: NIMTeamType.typeNormal,
        avatar: avatar,
        intro: intro,
        // 高级群默认设置
        joinMode: NIMTeamJoinMode.joinModeApply, // 需要验证
        agreeMode: NIMTeamAgreeMode.agreeModeNoAuth, // 被邀请人无需同意
        inviteMode: NIMTeamInviteMode.inviteModeAll, // 所有人可邀请
        updateInfoMode: NIMTeamUpdateInfoMode.updateInfoModeManager, // 仅管理员可改群信息
      );

      final result = await NimCore.instance.teamService.createTeam(
        params,
        inviteeAccids,
        null, // postscript
        null, // antispamConfig
      );

      if (result.isSuccess && result.data != null) {
        final teamId = result.data!.team?.teamId ?? '';
        _log('群组创建成功: teamId=$teamId');

        // 生成群聊会话 ID
        String? conversationId;
        final convResult = await NimCore.instance.conversationIdUtil
            .teamConversationId(teamId);
        if (convResult.isSuccess && convResult.data != null) {
          conversationId = convResult.data!;
        }

        // 在本地会话列表中添加群聊会话
        if (conversationId != null) {
          await TZConversationService.instance.addOrUpdateLocalConversation(
            conversationId: conversationId,
            type: NIMConversationType.team,
            targetId: teamId,
            name: name,
            avatar: avatar ?? '',
          );
        }

        return (
          success: true,
          teamId: teamId,
          conversationId: conversationId,
          error: null,
        );
      } else {
        _log('群组创建失败: ${result.errorDetails}');
        return (
          success: false,
          teamId: null,
          conversationId: null,
          error: result.errorDetails ?? '创建失败',
        );
      }
    } catch (e) {
      _log('创建群组异常: $e');
      return (success: false, teamId: null, conversationId: null, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 获取群组信息
  // ═══════════════════════════════════════════════════════

  /// 获取群组信息
  Future<NIMTeam?> getTeamInfo(String teamId) async {
    if (!_isIMReady) return null;

    try {
      final result = await NimCore.instance.teamService
          .getTeamInfo(teamId, NIMTeamType.typeNormal);

      if (result.isSuccess && result.data != null) {
        return result.data!;
      }
      _log('获取群信息失败: ${result.errorDetails}');
      return null;
    } catch (e) {
      _log('获取群信息异常: $e');
      return null;
    }
  }

  /// 获取已加入的群组列表
  Future<List<NIMTeam>> getJoinedTeamList() async {
    if (!_isIMReady) return [];

    try {
      final result = await NimCore.instance.teamService
          .getJoinedTeamList([NIMTeamType.typeNormal]);

      if (result.isSuccess && result.data != null) {
        _log('已加入群组: ${result.data!.length} 个');
        return result.data!;
      }
      return [];
    } catch (e) {
      _log('获取已加入群组异常: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // 群成员管理
  // ═══════════════════════════════════════════════════════

  /// 获取群成员列表
  Future<List<NIMTeamMember>> getTeamMembers(String teamId) async {
    if (!_isIMReady) return [];

    try {
      final queryOption = NIMTeamMemberQueryOption(
        roleQueryType: NIMTeamMemberRoleQueryType.memberRoleQueryTypeAll,
        limit: 200,
        onlyChatBanned: false,
      );

      final result = await NimCore.instance.teamService
          .getTeamMemberList(teamId, NIMTeamType.typeNormal, queryOption);

      if (result.isSuccess && result.data != null) {
        final members = result.data!.memberList ?? [];
        _log('群成员列表: ${members.length} 人');
        return members;
      }
      return [];
    } catch (e) {
      _log('获取群成员异常: $e');
      return [];
    }
  }

  /// 邀请成员加入群组
  Future<({bool success, String? error})> inviteMembers(
    String teamId,
    List<String> accids,
  ) async {
    if (!_isIMReady) {
      return (success: false, error: 'IM 未就绪');
    }

    try {
      _log('邀请成员: $accids 加入群 $teamId');
      final result = await NimCore.instance.teamService
          .inviteMember(teamId, NIMTeamType.typeNormal, accids, null);

      if (result.isSuccess) {
        _log('邀请成功');
        _memberChangedController.add(teamId);
        return (success: true, error: null);
      } else {
        return (success: false, error: result.errorDetails ?? '邀请失败');
      }
    } catch (e) {
      _log('邀请成员异常: $e');
      return (success: false, error: '$e');
    }
  }

  /// 踢出群成员
  Future<({bool success, String? error})> kickMember(
    String teamId,
    List<String> accids,
  ) async {
    if (!_isIMReady) {
      return (success: false, error: 'IM 未就绪');
    }

    try {
      _log('踢出成员: $accids 从群 $teamId');
      final result = await NimCore.instance.teamService
          .kickMember(teamId, NIMTeamType.typeNormal, accids);

      if (result.isSuccess) {
        _log('踢出成功');
        _memberChangedController.add(teamId);
        return (success: true, error: null);
      } else {
        return (success: false, error: result.errorDetails ?? '踢出失败');
      }
    } catch (e) {
      _log('踢出成员异常: $e');
      return (success: false, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 修改群信息
  // ═══════════════════════════════════════════════════════

  /// 修改群名称
  Future<bool> updateTeamName(String teamId, String newName) async {
    if (!_isIMReady) return false;

    try {
      final params = NIMUpdateTeamInfoParams(name: newName);
      final result = await NimCore.instance.teamService
          .updateTeamInfo(teamId, NIMTeamType.typeNormal, params, null);

      if (result.isSuccess) {
        _log('群名称更新成功: $newName');
        // 同步更新本地会话名称
        _updateLocalConversationName(teamId, newName);
        return true;
      }
      return false;
    } catch (e) {
      _log('更新群名称异常: $e');
      return false;
    }
  }

  /// 修改群公告
  Future<bool> updateTeamAnnouncement(
    String teamId,
    String announcement,
  ) async {
    if (!_isIMReady) return false;

    try {
      final params = NIMUpdateTeamInfoParams(announcement: announcement);
      final result = await NimCore.instance.teamService
          .updateTeamInfo(teamId, NIMTeamType.typeNormal, params, null);

      if (result.isSuccess) {
        _log('群公告更新成功');
        return true;
      }
      return false;
    } catch (e) {
      _log('更新群公告异常: $e');
      return false;
    }
  }

  /// 修改群介绍
  Future<bool> updateTeamIntro(String teamId, String intro) async {
    if (!_isIMReady) return false;

    try {
      final params = NIMUpdateTeamInfoParams(intro: intro);
      final result = await NimCore.instance.teamService
          .updateTeamInfo(teamId, NIMTeamType.typeNormal, params, null);

      if (result.isSuccess) {
        _log('群介绍更新成功');
        return true;
      }
      return false;
    } catch (e) {
      _log('更新群介绍异常: $e');
      return false;
    }
  }

  /// 修改我的群昵称
  Future<bool> updateMyTeamNick(String teamId, String nick) async {
    if (!_isIMReady) return false;

    try {
      final params = NIMUpdateSelfMemberInfoParams(teamNick: nick);
      final result = await NimCore.instance.teamService
          .updateSelfTeamMemberInfo(
              teamId, NIMTeamType.typeNormal, params);

      if (result.isSuccess) {
        _log('我的群昵称更新成功: $nick');
        return true;
      }
      return false;
    } catch (e) {
      _log('更新群昵称异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 群组操作
  // ═══════════════════════════════════════════════════════

  /// 退出群组
  Future<({bool success, String? error})> leaveTeam(String teamId) async {
    if (!_isIMReady) {
      return (success: false, error: 'IM 未就绪');
    }

    try {
      _log('退出群组: $teamId');
      final result = await NimCore.instance.teamService
          .leaveTeam(teamId, NIMTeamType.typeNormal);

      if (result.isSuccess) {
        _log('退出群组成功');
        return (success: true, error: null);
      } else {
        return (success: false, error: result.errorDetails ?? '退出失败');
      }
    } catch (e) {
      _log('退出群组异常: $e');
      return (success: false, error: '$e');
    }
  }

  /// 解散群组（仅群主）
  Future<({bool success, String? error})> dismissTeam(String teamId) async {
    if (!_isIMReady) {
      return (success: false, error: 'IM 未就绪');
    }

    try {
      _log('解散群组: $teamId');
      final result = await NimCore.instance.teamService
          .dismissTeam(teamId, NIMTeamType.typeNormal);

      if (result.isSuccess) {
        _log('解散群组成功');
        return (success: true, error: null);
      } else {
        return (success: false, error: result.errorDetails ?? '解散失败');
      }
    } catch (e) {
      _log('解散群组异常: $e');
      return (success: false, error: '$e');
    }
  }

  /// 转让群主
  Future<({bool success, String? error})> transferOwner(
    String teamId,
    String newOwnerAccid, {
    bool leave = false,
  }) async {
    if (!_isIMReady) {
      return (success: false, error: 'IM 未就绪');
    }

    try {
      _log('转让群主: $teamId -> $newOwnerAccid');
      final result = await NimCore.instance.teamService
          .transferTeamOwner(
              teamId, NIMTeamType.typeNormal, newOwnerAccid, leave);

      if (result.isSuccess) {
        _log('转让群主成功');
        _memberChangedController.add(teamId);
        return (success: true, error: null);
      } else {
        return (success: false, error: result.errorDetails ?? '转让失败');
      }
    } catch (e) {
      _log('转让群主异常: $e');
      return (success: false, error: '$e');
    }
  }

  /// 设置/取消管理员
  Future<bool> setManager(
    String teamId,
    String accid, {
    required bool isManager,
  }) async {
    if (!_isIMReady) return false;

    try {
      final role = isManager
          ? NIMTeamMemberRole.memberRoleManager
          : NIMTeamMemberRole.memberRoleNormal;

      final result = await NimCore.instance.teamService
          .updateTeamMemberRole(
              teamId, NIMTeamType.typeNormal, [accid], role);

      if (result.isSuccess) {
        _log('设置管理员成功: $accid -> $isManager');
        _memberChangedController.add(teamId);
        return true;
      }
      return false;
    } catch (e) {
      _log('设置管理员异常: $e');
      return false;
    }
  }

  /// 群禁言
  Future<bool> setTeamMute(String teamId, {required bool mute}) async {
    if (!_isIMReady) return false;

    try {
      final mode = mute
          ? NIMTeamChatBannedMode.chatBannedModeBannedNormal
          : NIMTeamChatBannedMode.chatBannedModeNone;

      final result = await NimCore.instance.teamService
          .setTeamChatBannedMode(teamId, NIMTeamType.typeNormal, mode);

      if (result.isSuccess) {
        _log('群禁言设置成功: $mute');
        return true;
      }
      return false;
    } catch (e) {
      _log('群禁言设置异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════════

  /// 判断当前用户是否是群主
  bool isOwner(NIMTeam team) {
    return team.ownerAccountId == _myAccid;
  }

  /// 判断当前用户是否是管理员或群主
  bool isManagerOrOwner(NIMTeamMember member) {
    return member.memberRole == NIMTeamMemberRole.memberRoleOwner ||
        member.memberRole == NIMTeamMemberRole.memberRoleManager;
  }

  /// 同步更新本地会话名称
  void _updateLocalConversationName(String teamId, String newName) {
    final convService = TZConversationService.instance;
    final conv = convService.conversations
        .where((c) => c.targetId == teamId)
        .firstOrNull;
    if (conv != null) {
      convService.addOrUpdateLocalConversation(
        conversationId: conv.conversationId,
        type: conv.type,
        targetId: teamId,
        name: newName,
        avatar: conv.avatar,
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // 日志 & 生命周期
  // ═══════════════════════════════════════════════════════

  void _log(String message) {
    debugPrint('[TZTeamService] $message');
  }

  void reset() {
    _teamCreatedSub?.cancel();
    _teamDismissedSub?.cancel();
    _teamInfoUpdatedSub?.cancel();
    _teamMemberJoinedSub?.cancel();
    _teamMemberLeftSub?.cancel();
    _teamMemberKickedSub?.cancel();
    _teamCreatedSub = null;
    _teamDismissedSub = null;
    _teamInfoUpdatedSub = null;
    _teamMemberJoinedSub = null;
    _teamMemberLeftSub = null;
    _teamMemberKickedSub = null;
  }

  @override
  void dispose() {
    reset();
    _teamUpdatedController.close();
    _memberChangedController.close();
    super.dispose();
  }
}
