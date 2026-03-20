/// 平台辅助 - 原生端（iOS/Android/macOS/Windows）
/// 使用 dart:io 进行平台检测
import 'dart:io';
import 'package:nim_core_v2/nim_core.dart';

NIMSDKOptions? buildNativeSDKOptions(String appKey) {
  if (Platform.isAndroid) {
    return NIMAndroidSDKOptions(
      appKey: appKey,
      shouldSyncUnreadCount: true,
      enableTeamMessageReadReceipt: true,
      shouldConsiderRevokedMessageUnreadCount: true,
      enablePreloadMessageAttachment: true,
    );
  } else if (Platform.isIOS) {
    return NIMIOSSDKOptions(
      appKey: appKey,
      shouldSyncUnreadCount: true,
      enableTeamMessageReadReceipt: true,
      shouldConsiderRevokedMessageUnreadCount: true,
      enablePreloadMessageAttachment: true,
    );
  } else if (Platform.isMacOS || Platform.isWindows) {
    return NIMPCSDKOptions(
      appKey: appKey,
      basicOption: NIMBasicOption(),
    );
  }
  return null;
}
