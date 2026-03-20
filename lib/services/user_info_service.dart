/// 途正英语 - 用户信息服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. 查询云信用户资料（头像、昵称）
/// 2. 本地缓存用户信息，避免重复查询
/// 3. 供聊天列表和聊天面板使用
///
/// 安全机制：
/// - 所有 NIM SDK 调用前都检查 IM 初始化和登录状态
/// - 防止 SDK 未初始化时原生层 abort() 导致闪退
///
/// 注意：这里查询的是云信侧的用户信息（name, avatar），
/// 业务侧的用户信息（角色、手机号等）由自建后端管理。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'im_service.dart';

/// 缓存的用户信息
class TZUserInfo {
  final String accid;
  final String name;
  final String avatar;
  final String? sign; // 个性签名
  final DateTime cachedAt;

  TZUserInfo({
    required this.accid,
    required this.name,
    required this.avatar,
    this.sign,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  /// 缓存是否过期（10 分钟）
  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes > 10;
}

class UserInfoService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final UserInfoService _instance = UserInfoService._internal();
  static UserInfoService get instance => _instance;
  UserInfoService._internal();

  // ═══════════════════════════════════════════════════════
  // 缓存
  // ═══════════════════════════════════════════════════════

  final Map<String, TZUserInfo> _cache = {};

  /// 获取缓存的用户信息（可能为 null）
  TZUserInfo? getCached(String accid) => _cache[accid];

  StreamSubscription<List<NIMUserInfo>>? _userProfileChangedSub;

  // ═══════════════════════════════════════════════════════
  // 安全检查
  // ═══════════════════════════════════════════════════════

  /// 检查 IM SDK 是否已初始化且已登录
  bool get _isIMReady =>
      IMService.instance.isInitialized && IMService.instance.isLoggedIn;

  // ═══════════════════════════════════════════════════════
  // 查询
  // ═══════════════════════════════════════════════════════

  /// 获取单个用户信息
  Future<TZUserInfo?> getUserInfo(String accid) async {
    // 先查缓存
    final cached = _cache[accid];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    // IM 未就绪时返回缓存（即使过期）或 null
    if (!_isIMReady) {
      _log('IM 未就绪，返回缓存或 null');
      return cached;
    }

    try {
      final result =
          await NimCore.instance.userService.getUserList([accid]);

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        final user = result.data!.first;
        final info = TZUserInfo(
          accid: user.accountId ?? accid,
          name: user.name ?? '',
          avatar: user.avatar ?? '',
          sign: user.sign,
        );
        _cache[accid] = info;
        return info;
      }
      return null;
    } catch (e) {
      _log('查询用户信息异常: $e');
      return null;
    }
  }

  /// 批量获取用户信息
  Future<Map<String, TZUserInfo>> getUserInfoBatch(
    List<String> accids,
  ) async {
    final result = <String, TZUserInfo>{};
    final needFetch = <String>[];

    // 先从缓存取
    for (final accid in accids) {
      final cached = _cache[accid];
      if (cached != null && !cached.isExpired) {
        result[accid] = cached;
      } else {
        needFetch.add(accid);
      }
    }

    // IM 未就绪时只返回缓存
    if (!_isIMReady) {
      _log('IM 未就绪，仅返回缓存数据');
      return result;
    }

    // 批量查询未缓存的（每次最多 150 个）
    if (needFetch.isNotEmpty) {
      try {
        // 分批查询
        for (var i = 0; i < needFetch.length; i += 150) {
          final batch = needFetch.sublist(
            i,
            i + 150 > needFetch.length ? needFetch.length : i + 150,
          );

          final queryResult =
              await NimCore.instance.userService.getUserList(batch);

          if (queryResult.isSuccess && queryResult.data != null) {
            for (final user in queryResult.data!) {
              final accid = user.accountId ?? '';
              if (accid.isNotEmpty) {
                final info = TZUserInfo(
                  accid: accid,
                  name: user.name ?? '',
                  avatar: user.avatar ?? '',
                  sign: user.sign,
                );
                _cache[accid] = info;
                result[accid] = info;
              }
            }
          }
        }
      } catch (e) {
        _log('批量查询用户信息异常: $e');
      }
    }

    return result;
  }

  /// 清除缓存
  void clearCache() {
    _cache.clear();
  }

  /// 注册用户资料变化监听（使用 Stream 方式）
  void setupListeners() {
    // IM 未就绪时不注册监听
    if (!_isIMReady) {
      _log('IM 未就绪，跳过用户资料监听注册');
      return;
    }

    _userProfileChangedSub =
        NimCore.instance.userService.onUserProfileChanged.listen((users) {
      _log('用户资料变化: ${users.length} 个');
      for (final user in users) {
        final accid = user.accountId ?? '';
        if (accid.isNotEmpty) {
          _cache[accid] = TZUserInfo(
            accid: accid,
            name: user.name ?? '',
            avatar: user.avatar ?? '',
            sign: user.sign,
          );
        }
      }
      notifyListeners();
    });
  }

  /// 重置服务状态（登出时调用）
  void reset() {
    _cache.clear();
    _userProfileChangedSub?.cancel();
    _userProfileChangedSub = null;
  }

  void _log(String message) {
    debugPrint('[UserInfoService] $message');
  }

  @override
  void dispose() {
    _userProfileChangedSub?.cancel();
    super.dispose();
  }
}
