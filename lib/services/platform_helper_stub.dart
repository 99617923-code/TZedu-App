/// 平台辅助 - Web 端桩文件
/// Web 端不支持 dart:io，返回默认值
import 'package:nim_core_v2/nim_core.dart';

NIMSDKOptions? buildNativeSDKOptions(String appKey) {
  // Web 端不走此路径（im_service.dart 中 kIsWeb 优先处理）
  return null;
}

Map<String, dynamic> collectNativeDeviceInfo() {
  return {
    'platform': 'web',
    'osVersion': '',
    'appVersion': '1.0.0',
  };
}
