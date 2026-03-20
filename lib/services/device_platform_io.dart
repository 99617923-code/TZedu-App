/// 设备平台辅助 - 原生端（iOS/Android/macOS/Windows）
import 'dart:io';
import 'package:nim_core_v2/nim_core.dart';

/// 收集原生平台设备信息
Map<String, dynamic> collectNativeDeviceInfo() {
  String platform = 'unknown';
  String osVersion = '';

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
    // Platform detection failed
  }

  return {
    'platform': platform,
    'osVersion': osVersion,
    'appVersion': '1.0.0',
  };
}

/// Stub: 此文件不需要 buildNativeSDKOptions，但条件导入要求签名一致
NIMSDKOptions? buildNativeSDKOptions(String appKey) => null;
