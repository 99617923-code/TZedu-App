/// 平台检测 - 原生端（dart:io 可用）
/// 火鹰科技出品
import 'dart:io';

/// 检查是否为桌面平台（macOS/Windows/Linux）
bool isDesktopPlatform() {
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// 检查是否为 macOS 平台
bool isMacOS() {
  return Platform.isMacOS;
}

/// 检查是否为 Windows 平台
bool isWindows() {
  return Platform.isWindows;
}
