/// 途正英语 - 认证服务层（自建后端 + 网易云信 IM）
/// 火鹰科技出品
///
/// 职责：
/// 1. 调用自建后端的登录/注册/验证码 API
/// 2. 获取业务 Token + IM Token + AppKey
/// 3. 自动登录网易云信 IM
/// 4. Token 持久化存储
/// 5. 单点登录（SSO）支持
///
/// 用户体系完全自建，零依赖第三方平台。
/// 网易云信只做 IM 通道，用户信息由自建后端管理。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/im_config.dart';
import 'im_service.dart';
import 'conversation_service.dart';
import 'chat_message_service.dart';
import 'user_info_service.dart';

/// 登录结果
class LoginResult {
  final bool success;
  final String? message;
  final UserProfile? userProfile;

  LoginResult({required this.success, this.message, this.userProfile});
}

/// 用户资料（自建后端返回）
class UserProfile {
  final String userId;
  final String nickname;
  final String avatar;
  final String role; // student / teacher / parent
  final String? phone;
  final String? email;
  final String? status;

  UserProfile({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.role,
    this.phone,
    this.email,
    this.status,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id']?.toString() ?? '',
      nickname: json['nickname'] ?? '',
      avatar: json['avatar'] ?? '',
      role: json['role'] ?? 'student',
      phone: json['phone'],
      email: json['email'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'nickname': nickname,
    'avatar': avatar,
    'role': role,
    'phone': phone,
    'email': email,
    'status': status,
  };
}

/// 搜索用户结果
class SearchUserResult {
  final bool success;
  final String? message;
  final SearchedUser? user;

  SearchUserResult({required this.success, this.message, this.user});
}

/// 搜索到的用户信息
class SearchedUser {
  final String userId;
  final String nickname;
  final String avatar;
  final String phone;
  final String role;
  final String accid; // IM 账号

  SearchedUser({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.phone,
    required this.role,
    required this.accid,
  });

  /// 角色显示名称
  String get roleLabel {
    switch (role) {
      case 'teacher': return '老师';
      case 'parent': return '家长';
      case 'admin': return '管理员';
      default: return '学生';
    }
  }
}

class AuthService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;
  AuthService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  UserProfile? _currentUser;
  UserProfile? get currentUser => _currentUser;

  String? _bizToken;
  String? get bizToken => _bizToken;

  String? _refreshToken;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 持久化 Key
  static const String _keyBizToken = 'tz_biz_token';
  static const String _keyRefreshToken = 'tz_refresh_token';
  static const String _keyImAccid = 'tz_im_accid';
  static const String _keyImToken = 'tz_im_token';
  static const String _keyImAppKey = 'tz_im_app_key';
  static const String _keyUserProfile = 'tz_user_profile';

  // ═══════════════════════════════════════════════════════
  // 图形验证码
  // ═══════════════════════════════════════════════════════

  /// 获取图形验证码
  /// 返回 { captchaId: String, captchaImage: String(base64 SVG) }
  Future<Map<String, dynamic>?> getCaptcha() async {
    try {
      final response = await http.get(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.captchaPath}'),
        headers: IMConfig.baseHeaders,
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == 200) {
          return body['data'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      _log('获取验证码异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 短信验证码
  // ═══════════════════════════════════════════════════════

  /// 发送短信验证码
  Future<({bool success, String message})> sendSmsCode(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.sendSmsCodePath}'),
        headers: IMConfig.baseHeaders,
        body: jsonEncode({'phone': phone}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        success: body['code'] == 200,
        message: (body['msg'] ?? '发送失败').toString(),
      );
    } catch (e) {
      return (success: false, message: '网络异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 注册
  // ═══════════════════════════════════════════════════════

  /// 注册新用户
  Future<({bool success, String message})> register({
    required String phone,
    required String password,
    required String nickname,
    String? captchaId,
    String? captchaCode,
  }) async {
    try {
      final params = <String, dynamic>{
        'phone': phone,
        'password': password,
        'nickname': nickname,
      };
      if (captchaId != null) params['captchaId'] = captchaId;
      if (captchaCode != null) params['captchaCode'] = captchaCode;

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.registerPath}'),
        headers: IMConfig.baseHeaders,
        body: jsonEncode(params),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        success: body['code'] == 200,
        message: (body['msg'] ?? '注册失败').toString(),
      );
    } catch (e) {
      return (success: false, message: '网络异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 登录
  // ═══════════════════════════════════════════════════════

  /// 手机号 + 密码登录
  Future<LoginResult> loginWithPassword(String phone, String password) async {
    return _doLogin(
      IMConfig.loginPath,
      {'phone': phone, 'password': password},
    );
  }

  /// 手机号 + 验证码登录（后端路径: /auth/sms-login）
  Future<LoginResult> loginWithSmsCode(String phone, String code) async {
    return _doLogin(
      IMConfig.smsLoginPath,
      {'phone': phone, 'smsCode': code},
    );
  }

  /// 微信授权登录
  Future<LoginResult> loginWithWechat(String wxCode) async {
    return _doLogin(
      IMConfig.loginPath,
      {'wx_code': wxCode},
    );
  }

  /// 执行登录（支持不同路径）
  Future<LoginResult> _doLogin(String apiPath, Map<String, dynamic> params) async {
    _isLoading = true;
    notifyListeners();

    try {
      _log('正在登录... ($apiPath)');

      // 1. 调用自建后端登录 API（带 X-App-Key）
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}$apiPath'),
        headers: IMConfig.baseHeaders,
        body: jsonEncode(params),
      );

      if (response.statusCode != 200 && response.statusCode != 401) {
        return LoginResult(success: false, message: '网络请求失败: ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = body['code'] as int?;

      if (code != 200) {
        return LoginResult(success: false, message: body['msg'] ?? '登录失败');
      }

      final data = body['data'] as Map<String, dynamic>;

      // 2. 解析用户信息
      _currentUser = UserProfile.fromJson(data['user_info']);
      _bizToken = data['biz_token'] as String;
      _refreshToken = data['refresh_token'] as String?;

      // 3. 解析 IM 凭证
      final imAuth = data['im_auth'] as Map<String, dynamic>;
      final accid = imAuth['accid']?.toString() ?? '';
      final imToken = imAuth['im_token'] as String;

      // 4. 从 im_auth 中获取 AppKey（后端下发）
      if (imAuth.containsKey('app_key') && imAuth['app_key'] != null) {
        IMConfig.setAppKey(imAuth['app_key'] as String);
        _log('已从后端获取 IM AppKey: ${IMConfig.appKey.substring(0, 8)}...');
      }

      // 5. 持久化存储
      await _saveTokens(accid, imToken);

      // 6. 登录网易云信 IM（异步执行，不阻塞业务登录）
      if (IMConfig.appKey.isNotEmpty) {
        _loginIMAsync(accid, imToken);
      } else {
        _log('AppKey 未配置，跳过 IM 登录');
      }

      _isLoggedIn = true;
      _log('登录成功: ${_currentUser?.nickname} (${_currentUser?.role})');

      return LoginResult(
        success: true,
        message: '登录成功',
        userProfile: _currentUser,
      );
    } catch (e) {
      _log('登录异常: $e');
      return LoginResult(success: false, message: '登录失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 自动登录（App 启动时）
  // ═══════════════════════════════════════════════════════

  /// 尝试自动登录（从本地存储恢复）
  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accid = prefs.getString(_keyImAccid);
      final imToken = prefs.getString(_keyImToken);
      final bizToken = prefs.getString(_keyBizToken);
      final refreshToken = prefs.getString(_keyRefreshToken);
      final userJson = prefs.getString(_keyUserProfile);
      final appKey = prefs.getString(_keyImAppKey);

      if (accid == null || imToken == null || bizToken == null) {
        _log('无本地凭证，需要重新登录');
        return false;
      }

      _bizToken = bizToken;
      _refreshToken = refreshToken;

      // 恢复 AppKey
      if (appKey != null && appKey.isNotEmpty) {
        IMConfig.setAppKey(appKey);
      }

      // 恢复用户信息
      if (userJson != null) {
        _currentUser = UserProfile.fromJson(jsonDecode(userJson));
      }

      // 先尝试调用 /auth/me 验证 biz_token 是否有效
      final meResult = await _fetchMe();
      if (!meResult) {
        // biz_token 过期，尝试用 refresh_token 刷新
        if (_refreshToken != null) {
          final refreshed = await refreshBizToken();
          if (!refreshed) {
            _log('Token 刷新失败，需要重新登录');
            await _clearTokens();
            return false;
          }
        } else {
          _log('无 refresh_token，需要重新登录');
          await _clearTokens();
          return false;
        }
      }

      // 登录 IM（异步执行，不阻塞自动登录）
      if (IMConfig.appKey.isNotEmpty) {
        final prefs2 = await SharedPreferences.getInstance();
        final savedAccid = prefs2.getString(_keyImAccid);
        final savedImToken = prefs2.getString(_keyImToken);
        if (savedAccid != null && savedImToken != null) {
          _loginIMAsync(savedAccid, savedImToken);
        }
      }

      _isLoggedIn = true;
      notifyListeners();
      _log('自动登录成功: ${_currentUser?.nickname}');
      return true;
    } catch (e) {
      _log('自动登录异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 登出
  // ═══════════════════════════════════════════════════════

  /// 登出
  Future<void> logout() async {
    try {
      // 通知后端登出（带 X-App-Key）
      if (_bizToken != null) {
        try {
          await http.post(
            Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.logoutPath}'),
            headers: IMConfig.authHeaders(_bizToken!),
          );
        } catch (_) {
          // 忽略后端登出失败
        }
      }

      // 登出 IM
      await IMService.instance.logout();

      // 重置 IM 相关服务
      TZConversationService.instance.reset();
      ChatMessageService.instance.reset();

      // 清除本地存储
      await _clearTokens();
      _currentUser = null;
      _bizToken = null;
      _refreshToken = null;
      _isLoggedIn = false;
      notifyListeners();

      _log('已登出');
    } catch (e) {
      _log('登出异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // Token 刷新
  // ═══════════════════════════════════════════════════════

  /// 刷新业务 Token（refresh_token 通过 POST body 传递）
  Future<bool> refreshBizToken() async {
    if (_refreshToken == null) return false;

    try {
      _log('正在刷新 Token...');

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.refreshTokenPath}'),
        headers: IMConfig.baseHeaders,
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == 200) {
          final data = body['data'] as Map<String, dynamic>;

          // 更新双令牌
          _bizToken = data['biz_token'] as String;
          _refreshToken = data['refresh_token'] as String?;

          // 如果返回了新的 IM Token，也更新
          if (data.containsKey('im_auth') && data['im_auth'] != null) {
            final imAuth = data['im_auth'] as Map<String, dynamic>;
            final accid = imAuth['accid']?.toString() ?? '';
            final imToken = imAuth['im_token'] as String;
            await _saveTokens(accid, imToken);

            if (imAuth.containsKey('app_key') && imAuth['app_key'] != null) {
              IMConfig.setAppKey(imAuth['app_key'] as String);
            }
          }

          // 持久化新的 token
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyBizToken, _bizToken!);
          if (_refreshToken != null) {
            await prefs.setString(_keyRefreshToken, _refreshToken!);
          }

          _log('Token 刷新成功');
          return true;
        }
      }

      _log('Token 刷新失败: ${response.statusCode}');
      return false;
    } catch (e) {
      _log('刷新 Token 异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 更新用户资料
  // ═══════════════════════════════════════════════════════

  /// 更新用户昵称/头像
  Future<bool> updateProfile({String? nickname, String? avatar}) async {
    if (_bizToken == null) return false;
    try {
      final params = <String, dynamic>{};
      if (nickname != null) params['nickname'] = nickname;
      if (avatar != null) params['avatar'] = avatar;

      final response = await http.put(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.updateProfilePath}'),
        headers: IMConfig.authHeaders(_bizToken!),
        body: jsonEncode(params),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == 200) {
          // 更新本地用户信息
          if (_currentUser != null) {
            _currentUser = UserProfile(
              userId: _currentUser!.userId,
              nickname: nickname ?? _currentUser!.nickname,
              avatar: avatar ?? _currentUser!.avatar,
              role: _currentUser!.role,
              phone: _currentUser!.phone,
              email: _currentUser!.email,
              status: _currentUser!.status,
            );
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyUserProfile, jsonEncode(_currentUser!.toJson()));
            notifyListeners();
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      _log('更新资料异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 搜索用户
  // ═══════════════════════════════════════════════════════

  /// 通过手机号搜索用户
  /// 返回用户信息（包含 accid），找不到返回 null
  Future<SearchUserResult> searchUserByPhone(String phone) async {
    if (_bizToken == null) {
      return SearchUserResult(success: false, message: '未登录，请先登录');
    }

    try {
      _log('搜索用户: $phone');

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.searchUserByPhonePath}'),
        headers: IMConfig.authHeaders(_bizToken!),
        body: jsonEncode({'phone': phone}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = body['code'] as int?;

      if (code == 200 && body['data'] != null) {
        final data = body['data'] as Map<String, dynamic>;
        return SearchUserResult(
          success: true,
          message: '找到用户',
          user: SearchedUser(
            userId: data['user_id']?.toString() ?? '',
            nickname: data['nickname']?.toString() ?? '',
            avatar: data['avatar']?.toString() ?? '',
            phone: data['phone']?.toString() ?? '',
            role: data['role']?.toString() ?? 'student',
            accid: data['accid']?.toString() ?? '',
          ),
        );
      } else {
        return SearchUserResult(
          success: false,
          message: body['msg']?.toString() ?? '未找到该用户',
        );
      }
    } catch (e) {
      _log('搜索用户异常: $e');
      return SearchUserResult(success: false, message: '网络异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 获取当前用户信息
  // ═══════════════════════════════════════════════════════

  /// 调用 /auth/me 获取最新用户信息和 IM 凭证
  Future<bool> _fetchMe() async {
    if (_bizToken == null) return false;

    try {
      final response = await http.get(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.mePath}'),
        headers: IMConfig.authHeaders(_bizToken!),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == 200) {
          final data = body['data'] as Map<String, dynamic>;

          // 更新用户信息
          _currentUser = UserProfile.fromJson(data['user_info']);

          // 更新 IM 凭证
          if (data.containsKey('im_auth') && data['im_auth'] != null) {
            final imAuth = data['im_auth'] as Map<String, dynamic>;
            final accid = imAuth['accid']?.toString() ?? '';
            final imToken = imAuth['im_token'] as String;
            await _saveTokens(accid, imToken);

            if (imAuth.containsKey('app_key') && imAuth['app_key'] != null) {
              IMConfig.setAppKey(imAuth['app_key'] as String);
            }
          }

          return true;
        }
      }

      return false;
    } catch (e) {
      _log('获取用户信息异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════

  /// 异步登录 IM（不阻塞主流程，防止原生 SDK 崩溃拖垮 App）
  Future<void> _loginIMAsync(String accid, String imToken) async {
    try {
      _log('异步登录 IM...');
      final imSuccess = await IMService.instance.login(accid, imToken);
      if (imSuccess) {
        await _initIMServices();
        _log('IM 登录并初始化服务成功');
      } else {
        _log('IM 登录失败，不影响业务功能');
      }
    } catch (e) {
      _log('IM 登录异常（已安全捕获）: $e');
    }
  }

  /// 初始化 IM 相关服务
  Future<void> _initIMServices() async {
    try {
      // ConversationService.initialize() 内部已包含数据同步等待逻辑
      // 先初始化 ChatMessageService（不依赖数据同步，可立即注册消息监听）
      ChatMessageService.instance.initialize();
      UserInfoService.instance.setupListeners();

      // ConversationService 初始化：
      // 1. 先从本地缓存恢复会话列表（秒级显示）
      // 2. 等待数据同步完成后从 SDK 加载最新数据覆盖
      // 3. 注册会话变化监听器
      // 4. 监听 IM 重连状态，自动刷新
      await TZConversationService.instance.initialize();

      _log('IM 服务初始化完成');
    } catch (e) {
      _log('IM 服务初始化异常: $e');
    }
  }

  /// 保存 Token 到本地
  Future<void> _saveTokens(String accid, String imToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyImAccid, accid);
    await prefs.setString(_keyImToken, imToken);
    if (_bizToken != null) {
      await prefs.setString(_keyBizToken, _bizToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    }
    if (IMConfig.appKey.isNotEmpty) {
      await prefs.setString(_keyImAppKey, IMConfig.appKey);
    }
    if (_currentUser != null) {
      await prefs.setString(_keyUserProfile, jsonEncode(_currentUser!.toJson()));
    }
  }

  /// 清除本地 Token
  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyImAccid);
    await prefs.remove(_keyImToken);
    await prefs.remove(_keyImAppKey);
    await prefs.remove(_keyBizToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserProfile);
    // 清除会话本地缓存
    await prefs.remove('tz_local_conversations');
    await prefs.remove('tz_local_unread_count');
  }

  void _log(String message) {
    debugPrint('[AuthService] $message');
  }
}
