/// 途正英语 - 在线更新服务
/// 火鹰科技出品
///
/// 支持全平台更新检查：
/// - iOS/Android: 引导到应用商店或下载APK
/// - macOS/Windows: 下载安装包自动更新
/// - Web: 刷新页面即可
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool forceUpdate;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.forceUpdate = false,
    required this.hasUpdate,
  });
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 获取当前平台标识
  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// 检查更新
  Future<UpdateInfo> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 请求更新接口
      final response = await http.get(
        Uri.parse('${AppConstants.updateCheckUrl}?platform=$platformName&version=$currentVersion'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UpdateInfo(
          latestVersion: data['latestVersion'] ?? currentVersion,
          currentVersion: currentVersion,
          downloadUrl: data['downloadUrl'],
          releaseNotes: data['releaseNotes'],
          forceUpdate: data['forceUpdate'] ?? false,
          hasUpdate: _compareVersions(currentVersion, data['latestVersion'] ?? currentVersion),
        );
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
    }

    // 默认返回无更新（API未就绪时）
    String currentVersion = AppConstants.appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
    } catch (_) {}

    return UpdateInfo(
      latestVersion: currentVersion,
      currentVersion: currentVersion,
      hasUpdate: false,
    );
  }

  /// 版本号比较
  bool _compareVersions(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// 执行更新
  Future<void> performUpdate(String? downloadUrl) async {
    if (downloadUrl == null) return;

    if (kIsWeb) {
      // Web端直接刷新
      return;
    }

    final uri = Uri.parse(downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 显示更新对话框
  static void showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('发现新版本', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('当前版本: ${info.currentVersion}',
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  const Spacer(),
                  Text('最新版本: ${info.latestVersion}',
                      style: const TextStyle(
                          color: Color(0xFF7C3AED), fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
            if (info.releaseNotes != null) ...[
              const SizedBox(height: 16),
              const Text('更新内容:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Text(info.releaseNotes!,
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13, height: 1.5)),
            ],
            if (info.forceUpdate) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('此版本为强制更新，请立即更新',
                          style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('稍后再说', style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              UpdateService().performUpdate(info.downloadUrl);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('立即更新', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
