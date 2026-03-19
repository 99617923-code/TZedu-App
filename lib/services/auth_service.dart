/// 途正英语 - 认证服务层（自建后端 + 网易云信 IM）
/// 火鹰科技出品
///
/// 职责：
/// 1. 调用自建后端的登录 API
/// 2. 获取业务 Token + IM Token + AppKey
/// 3. 自动登录网易云信 IM
/// 4. Token 持久化存储
/// 5. 单点登录（SSO）支持
///
/// 用户体系完全自建，零依赖 Manus。
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

  UserProfile({
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.role,
    this.phone,
    this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id']?.toString() ?? '',
      nickname: json['nickname'] ?? '',
      avatar: json['avatar'] ?? '',
      role: json['role'] ?? 'student',
      phone: json['phone'],
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'nickname': nickname,
    'avatar': avatar,
    'role': role,
    'phone': phone,
    'email': email,
  };
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
  // 登录
  // ═══════════════════════════════════════════════════════

  /// 手机号 + 密码登录（适配后端当前接口）
  Future<LoginResult> loginWithPassword(String phone, String password) async {
    return _doLogin({
      'phone': phone,
      'password': password,
    });
  }

  /// 手机号 + 验证码登录
  Future<LoginResult> loginWithPhone(String phone, String code) async {
    return _doLogin({
      'phone': phone,
      'code': code,
    });
  }

  /// 微信授权登录
  Future<LoginResult> loginWithWechat(String wxCode) async {
    return _doLogin({
      'wx_code': wxCode,
    });
  }

  /// 执行登录
  Future<LoginResult> _doLogin(Map<String, dynamic> params) async {
    _isLoading = true;
    notifyListeners();

    try {
      _log('正在登录...');

      // 1. 调用自建后端登录 API
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.loginPath}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(params),
      );

      if (response.statusCode != 200) {
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
        _log('已从后端获取 AppKey');
      }

      // 5. 持久化存储
      await _saveTokens(accid, imToken);

      // 6. 登录网易云信 IM（需要 AppKey 已设置）
      if (IMConfig.appKey.isNotEmpty) {
        final imSuccess = await IMService.instance.login(accid, imToken);
        if (!imSuccess) {
          _log('IM 登录失败，但业务登录成功');
          // IM 登录失败不阻塞业务，后续会自动重连
        } else {
          // 7. 初始化 IM 相关服务
          await _initIMServices();
        }
      } else {
        _log('AppKey 未配置，跳过 IM 登录');
      }

      _isLoggedIn = true;
      _log('登录成功: ${_currentUser?.nickname}');

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

      // 登录 IM
      if (IMConfig.appKey.isNotEmpty) {
        final imSuccess = await IMService.instance.login(accid, imToken);
        if (imSuccess) {
          await _initIMServices();
        } else {
          _log('IM Token 过期，尝试重新获取');
          // IM 登录失败不阻塞，业务仍然可用
        }
      }

      _isLoggedIn = true;
      notifyListeners();
      _log('自动登录成功');
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
      // 通知后端登出
      if (_bizToken != null) {
        try {
          await http.post(
            Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.logoutPath}'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_bizToken',
            },
          );
        } catch (_) {
          // 忽略后端登出失败
        }
      }

      // 登出 IM
      await IMService.instance.logout();

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
  // Token 刷新（适配后端：refresh_token 通过 POST body 传递）
  // ═══════════════════════════════════════════════════════

  /// 刷新业务 Token
  /// 后端接口：POST /api/v1/auth/refresh-token
  /// 请求体：{ "refresh_token": "xxx" }
  /// 响应体：{ "code": 200, "data": { "biz_token": "xxx", "refresh_token": "xxx" } }
  Future<bool> refreshBizToken() async {
    if (_refreshToken == null) return false;

    try {
      _log('正在刷新 Token...');

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.refreshTokenPath}'),
        headers: {'Content-Type': 'application/json'},
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

            // 更新 AppKey
            if (imAuth.containsKey('app_key') && imAuth['app_key'] != null) {
              IMConfig.setAppKey(imAuth['app_key'] as String);
            }
          }

          // 持久化新的 biz_token 和 refresh_token
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
  // 获取当前用户信息
  // ═══════════════════════════════════════════════════════

  /// 调用 /auth/me 获取最新用户信息和 IM 凭证
  Future<bool> _fetchMe() async {
    if (_bizToken == null) return false;

    try {
      final response = await http.get(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.mePath}'),
        headers: {'Authorization': 'Bearer $_bizToken'},
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

            // 更新 AppKey
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

  /// 初始化 IM 相关服务
  Future<void> _initIMServices() async {
    await TZConversationService.instance.initialize();
    ChatMessageService.instance.initialize();
    UserInfoService.instance.setupListeners();
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
  }

  void _log(String message) {
    debugPrint('[AuthService] $message');
  }
}
