/// 途正英语 - 认证服务层（自建后端 + 网易云信 IM）
/// 火鹰科技出品
///
/// 职责：
/// 1. 调用自建后端的登录 API
/// 2. 获取业务 Token + IM Token
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

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 持久化 Key
  static const String _keyBizToken = 'tz_biz_token';
  static const String _keyImAccid = 'tz_im_accid';
  static const String _keyImToken = 'tz_im_token';
  static const String _keyUserProfile = 'tz_user_profile';

  // ═══════════════════════════════════════════════════════
  // 登录
  // ═══════════════════════════════════════════════════════

  /// 手机号 + 验证码登录
  Future<LoginResult> loginWithPhone(String phone, String code) async {
    return _doLogin({
      'login_type': 'phone',
      'phone': phone,
      'code': code,
    });
  }

  /// 手机号 + 密码登录
  Future<LoginResult> loginWithPassword(String phone, String password) async {
    return _doLogin({
      'login_type': 'password',
      'phone': phone,
      'password': password,
    });
  }

  /// 微信授权登录
  Future<LoginResult> loginWithWechat(String wxCode) async {
    return _doLogin({
      'login_type': 'wechat',
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

      // 3. 解析 IM 凭证
      final imAuth = data['im_auth'] as Map<String, dynamic>;
      final accid = imAuth['accid'] as String;
      final imToken = imAuth['im_token'] as String;

      // 4. 持久化存储
      await _saveTokens(accid, imToken);

      // 5. 登录网易云信 IM
      final imSuccess = await IMService.instance.login(accid, imToken);
      if (!imSuccess) {
        _log('IM 登录失败，但业务登录成功');
        // IM 登录失败不阻塞业务，后续会自动重连
      }

      // 6. 初始化 IM 相关服务
      if (imSuccess) {
        await _initIMServices();
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
      final userJson = prefs.getString(_keyUserProfile);

      if (accid == null || imToken == null || bizToken == null) {
        _log('无本地凭证，需要重新登录');
        return false;
      }

      _bizToken = bizToken;

      // 恢复用户信息
      if (userJson != null) {
        _currentUser = UserProfile.fromJson(jsonDecode(userJson));
      }

      // 登录 IM
      final imSuccess = await IMService.instance.login(accid, imToken);
      if (imSuccess) {
        await _initIMServices();
        _isLoggedIn = true;
        notifyListeners();
        _log('自动登录成功');
        return true;
      } else {
        _log('IM Token 过期，需要重新登录');
        await _clearTokens();
        return false;
      }
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
      // 通知后端登出（可选）
      if (_bizToken != null) {
        try {
          await http.post(
            Uri.parse('${IMConfig.apiBaseUrl}/api/v1/auth/logout'),
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

  /// 刷新业务 Token
  Future<bool> refreshToken() async {
    if (_bizToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.refreshTokenPath}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_bizToken',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['code'] == 200) {
          final data = body['data'] as Map<String, dynamic>;
          _bizToken = data['biz_token'] as String;

          // 如果返回了新的 IM Token，也更新
          if (data.containsKey('im_auth')) {
            final imAuth = data['im_auth'] as Map<String, dynamic>;
            await _saveTokens(imAuth['accid'], imAuth['im_token']);
          }

          return true;
        }
      }
      return false;
    } catch (e) {
      _log('刷新 Token 异常: $e');
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
    if (_currentUser != null) {
      await prefs.setString(_keyUserProfile, jsonEncode(_currentUser!.toJson()));
    }
  }

  /// 清除本地 Token
  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyImAccid);
    await prefs.remove(_keyImToken);
    await prefs.remove(_keyBizToken);
    await prefs.remove(_keyUserProfile);
  }

  void _log(String message) {
    debugPrint('[AuthService] $message');
  }
}
