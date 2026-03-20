/// 途正英语 - 设备管理服务层
/// 火鹰科技出品
///
/// 职责：
/// 1. 设备注册（App 启动时自动注册）
/// 2. 设备心跳（保持在线状态）
/// 3. 推送 Token 更新
/// 4. 设备下线

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/im_config.dart';
import 'auth_service.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  static DeviceService get instance => _instance;
  DeviceService._internal();

  Timer? _heartbeatTimer;
  String? _deviceId;

  String? get _token => AuthService.instance.bizToken;

  // ═══════════════════════════════════════════════════════
  // 设备注册
  // ═══════════════════════════════════════════════════════

  /// 注册/更新设备信息（登录成功后调用）
  Future<bool> registerDevice() async {
    if (_token == null) return false;

    try {
      final deviceInfo = _collectDeviceInfo();

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.deviceRegisterPath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode(deviceInfo),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>?;
        _deviceId = data?['deviceId']?.toString();
        _log('设备注册成功: $_deviceId');
        _startHeartbeat();
        return true;
      }

      _log('设备注册失败: ${body['msg']}');
      return false;
    } catch (e) {
      _log('设备注册异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 设备心跳
  // ═══════════════════════════════════════════════════════

  /// 启动心跳定时器（每5分钟一次）
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _sendHeartbeat();
    });
  }

  /// 发送心跳
  Future<void> _sendHeartbeat() async {
    if (_token == null) return;

    try {
      await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.deviceHeartbeatPath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          if (_deviceId != null) 'deviceId': _deviceId,
        }),
      );
    } catch (e) {
      _log('心跳异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 推送 Token
  // ═══════════════════════════════════════════════════════

  /// 更新推送 Token（获取到推送 Token 后调用）
  Future<bool> updatePushToken(String pushToken, {String provider = 'apns'}) async {
    if (_token == null) return false;

    try {
      final response = await http.put(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.devicePushTokenPath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          'pushToken': pushToken,
          'provider': provider,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['code'] == 200;
    } catch (e) {
      _log('更新推送Token异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 设备下线
  // ═══════════════════════════════════════════════════════

  /// 设备下线（登出时调用）
  Future<void> offline() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_token == null) return;

    try {
      await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.deviceOfflinePath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          if (_deviceId != null) 'deviceId': _deviceId,
        }),
      );
      _log('设备已下线');
    } catch (e) {
      _log('设备下线异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════

  Map<String, dynamic> _collectDeviceInfo() {
    String platform = 'unknown';
    String osVersion = '';

    if (!kIsWeb) {
      try {
        if (Platform.isIOS) {
          platform = 'ios';
          osVersion = Platform.operatingSystemVersion;
        } else if (Platform.isAndroid) {
          platform = 'android';
          osVersion = Platform.operatingSystemVersion;
        } else if (Platform.isMacOS) {
          platform = 'macos';
          osVersion = Platform.operatingSystemVersion;
        } else if (Platform.isWindows) {
          platform = 'windows';
          osVersion = Platform.operatingSystemVersion;
        } else if (Platform.isLinux) {
          platform = 'linux';
          osVersion = Platform.operatingSystemVersion;
        }
      } catch (_) {
        // Platform not available
      }
    } else {
      platform = 'web';
    }

    return {
      'platform': platform,
      'osVersion': osVersion,
      'appVersion': '1.0.0',
    };
  }

  void _log(String message) {
    debugPrint('[DeviceService] $message');
  }
}
