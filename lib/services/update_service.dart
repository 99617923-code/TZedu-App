/// 途正英语 - 在线更新服务（基于 GitHub Releases）
/// 火鹰科技出品
///
/// 真实可用的更新检查方案：
/// - 通过 GitHub Releases API 获取最新版本信息
/// - 自动匹配当前平台的下载资源（.exe / .dmg / .apk / .ipa）
/// - 支持强制更新、更新日志、下载链接
/// - 无需自建后台，发布新版本只需创建 GitHub Release
///
/// 后续迁移到自建后台时，只需修改 _fetchLatestRelease() 方法即可
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';
import '../config/theme.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final bool forceUpdate;
  final bool hasUpdate;
  final String? htmlUrl; // GitHub Release 页面链接

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.forceUpdate = false,
    required this.hasUpdate,
    this.htmlUrl,
  });
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// GitHub 仓库信息
  static const String _owner = '99617923-code';
  static const String _repo = 'TZedu-App';
  static const String _apiBase = 'https://api.github.com';

  /// 获取当前平台标识
  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  /// 各平台对应的安装包文件扩展名
  String get _platformAssetExtension {
    if (kIsWeb) return '';
    if (Platform.isIOS) return '.ipa';
    if (Platform.isAndroid) return '.apk';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return '.exe';
    return '';
  }

  /// 检查更新 — 真实调用 GitHub Releases API
  Future<UpdateInfo> checkForUpdate() async {
    String currentVersion = AppConstants.appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
    } catch (_) {}

    try {
      final releaseData = await _fetchLatestRelease();
      if (releaseData == null) {
        return _noUpdate(currentVersion);
      }

      // 解析版本号（GitHub tag 格式: v1.0.0 或 1.0.0）
      String latestVersion = (releaseData['tag_name'] as String? ?? currentVersion)
          .replaceFirst(RegExp(r'^v'), '');

      // 解析更新日志
      String? releaseNotes = releaseData['body'] as String?;

      // 解析 GitHub Release 页面链接
      String? htmlUrl = releaseData['html_url'] as String?;

      // 检查 release body 中是否包含 [FORCE_UPDATE] 标记
      bool forceUpdate = releaseNotes?.contains('[FORCE_UPDATE]') ?? false;
      // 清理标记
      releaseNotes = releaseNotes?.replaceAll('[FORCE_UPDATE]', '').trim();

      // 查找当前平台对应的下载资源
      String? downloadUrl = _findPlatformAsset(releaseData);
      // 如果没有找到平台特定资源，使用 Release 页面链接
      downloadUrl ??= htmlUrl;

      bool hasUpdate = _compareVersions(currentVersion, latestVersion);

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
        hasUpdate: hasUpdate,
        htmlUrl: htmlUrl,
      );
    } catch (e) {
      debugPrint('检查更新失败: $e');
      return _noUpdate(currentVersion);
    }
  }

  /// 从 GitHub API 获取最新 Release
  Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    final url = '$_apiBase/repos/$_owner/$_repo/releases/latest';
    debugPrint('正在检查更新: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'TZedu-App/${AppConstants.appVersion}',
      },
    ).timeout(const Duration(seconds: 15));

    debugPrint('GitHub API 响应状态: ${response.statusCode}');

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    // 404 表示还没有 Release
    if (response.statusCode == 404) {
      debugPrint('仓库暂无 Release');
      return null;
    }

    return null;
  }

  /// 在 Release assets 中查找当前平台的安装包
  String? _findPlatformAsset(Map<String, dynamic> releaseData) {
    final assets = releaseData['assets'] as List<dynamic>?;
    if (assets == null || assets.isEmpty) return null;

    final ext = _platformAssetExtension;
    if (ext.isEmpty) return null;

    // 优先精确匹配平台名称
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.contains(platformName) && name.endsWith(ext)) {
        return asset['browser_download_url'] as String?;
      }
    }

    // 其次匹配扩展名
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith(ext)) {
        return asset['browser_download_url'] as String?;
      }
    }

    return null;
  }

  /// 版本号比较（语义化版本: major.minor.patch）
  bool _compareVersions(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final l = i < latestParts.length ? latestParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (e) {
      debugPrint('版本号解析失败: $e');
    }
    return false;
  }

  /// 无更新时的默认返回
  UpdateInfo _noUpdate(String currentVersion) {
    return UpdateInfo(
      latestVersion: currentVersion,
      currentVersion: currentVersion,
      hasUpdate: false,
    );
  }

  /// 执行更新 — 打开下载链接
  Future<void> performUpdate(String? downloadUrl) async {
    if (downloadUrl == null || downloadUrl.isEmpty) return;

    if (kIsWeb) {
      // Web 端刷新页面即可（由 service worker 处理）
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
            const Text('发现新版本',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本号对比
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('v${info.currentVersion}',
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 13, fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 14, color: Color(0xFF9CA3AF)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('v${info.latestVersion}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),

            // 更新内容
            if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('更新内容:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(info.releaseNotes!,
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 13, height: 1.6)),
                ),
              ),
            ],

            // 强制更新提示
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
                          style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
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
              child: const Text('稍后再说',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              UpdateService().performUpdate(info.downloadUrl);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: TZColors.primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('立即更新',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 显示"已是最新版本"提示
  static void showUpToDateSnackBar(BuildContext context, String version) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('当前已是最新版本 v$version',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: TZColors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
