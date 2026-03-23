/// 途正英语 - 版本管理服务
/// 火鹰科技出品
///
/// 提供版本历史的读取、后端同步、上报机制
/// 前端内置版本数据 + 后端 API 获取远程版本数据，两者合并展示
/// 后端可通过 API 拉取前端版本数据并存储管理

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/im_config.dart';
import '../models/app_version.dart';
import '../data/changelog_data.dart';
import 'auth_service.dart';

class VersionService extends ChangeNotifier {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  /// 合并后的完整版本列表（本地 + 远程）
  List<AppVersion> _versions = [];
  List<AppVersion> get versions => _versions;

  /// 是否正在加载
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 最后一次同步时间
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 错误信息
  String? _error;
  String? get error => _error;

  // ═══════════════════════════════════════════════════════
  // 初始化和加载
  // ═══════════════════════════════════════════════════════

  /// 初始化：先加载本地数据，再尝试从后端拉取
  Future<void> initialize({String? authToken}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 1. 先加载内置版本数据（秒级显示）
    _versions = List.from(appVersionHistory);
    notifyListeners();

    // 2. 尝试从后端拉取最新版本数据
    final token = authToken ?? AuthService.instance.bizToken;
    if (token != null) {
      try {
        final remoteVersions = await _fetchRemoteVersions(token);
        if (remoteVersions.isNotEmpty) {
          _mergeVersions(remoteVersions);
        }
        _lastSyncTime = DateTime.now();
      } catch (e) {
        debugPrint('[VersionService] 从后端拉取版本数据失败: $e');
        // 失败时继续使用本地数据，不影响展示
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 获取所有版本（已排序，最新在前）
  List<AppVersion> getAllVersions() {
    if (_versions.isEmpty) {
      return List.from(appVersionHistory);
    }
    return _versions;
  }

  /// 获取指定类型的版本
  List<AppVersion> getVersionsByType(String type) {
    return getAllVersions().where((v) => v.type == type).toList();
  }

  /// 获取最新版本
  AppVersion? getLatestVersion() {
    final all = getAllVersions();
    return all.isNotEmpty ? all.first : null;
  }

  /// 获取指定版本
  AppVersion? getVersion(String version) {
    try {
      return getAllVersions().firstWhere((v) => v.version == version);
    } catch (_) {
      return null;
    }
  }

  /// 获取版本统计
  Map<String, int> getStatistics() {
    final all = getAllVersions();
    int totalFeats = 0;
    int totalFixes = 0;
    int totalImproves = 0;
    for (final v in all) {
      totalFeats += v.featCount;
      totalFixes += v.fixCount;
      totalImproves += v.improveCount;
    }
    return {
      'total_versions': all.length,
      'total_features': totalFeats,
      'total_fixes': totalFixes,
      'total_improvements': totalImproves,
      'total_changes': all.fold(0, (sum, v) => sum + v.changes.length),
    };
  }

  // ═══════════════════════════════════════════════════════
  // 后端 API 交互
  // ═══════════════════════════════════════════════════════

  /// 获取有效的 Token（如果过期则自动刷新）
  Future<String?> _getValidToken(String? providedToken) async {
    // 优先使用传入的 token
    String? token = providedToken ?? AuthService.instance.bizToken;
    if (token == null) return null;

    // 尝试验证 token 是否有效（通过一个轻量级请求）
    // 如果后续请求返回 401/403，会自动尝试刷新
    return token;
  }

  /// 带自动 Token 刷新的 HTTP 请求封装
  Future<http.Response> _authenticatedRequest({
    required String method,
    required String url,
    required String token,
    String? body,
  }) async {
    // 第一次请求
    final headers = IMConfig.authHeaders(token);
    http.Response response;

    if (method == 'GET') {
      response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
    } else {
      response = await http.post(Uri.parse(url), headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    }

    // 如果返回 401 或 403，尝试刷新 Token 后重试
    if (response.statusCode == 401 || response.statusCode == 403) {
      debugPrint('[VersionService] Token 可能过期 (${response.statusCode})，尝试刷新...');

      final refreshed = await AuthService.instance.refreshBizToken();
      if (refreshed) {
        final newToken = AuthService.instance.bizToken;
        if (newToken != null) {
          debugPrint('[VersionService] Token 刷新成功，重试请求...');
          final newHeaders = IMConfig.authHeaders(newToken);

          if (method == 'GET') {
            response = await http.get(Uri.parse(url), headers: newHeaders)
                .timeout(const Duration(seconds: 15));
          } else {
            response = await http.post(Uri.parse(url), headers: newHeaders, body: body)
                .timeout(const Duration(seconds: 15));
          }
        }
      } else {
        debugPrint('[VersionService] Token 刷新失败');
      }
    }

    return response;
  }

  /// 从后端拉取版本列表
  /// GET /api/v1/app/versions
  Future<List<AppVersion>> _fetchRemoteVersions(String authToken) async {
    final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions';
    debugPrint('[VersionService] 正在从后端拉取版本数据: $url');

    final response = await _authenticatedRequest(
      method: 'GET',
      url: url,
      token: authToken,
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      if (body['code'] == 200) {
        final data = body['data'] as List<dynamic>? ?? [];
        debugPrint('[VersionService] 从后端拉取到 ${data.length} 个版本');
        return data
            .map((e) => AppVersion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      debugPrint('[VersionService] 后端业务码: ${body['code']}, msg: ${body['msg']}');
    }

    debugPrint('[VersionService] 后端返回 HTTP ${response.statusCode}: ${response.body}');
    return [];
  }

  /// 上报本地版本数据到后端（管理员操作）
  /// POST /api/v1/app/versions/sync
  /// 返回 (bool success, String message) 元组
  Future<({bool success, String message})> syncToBackend(String authToken) async {
    try {
      final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions/sync';
      debugPrint('[VersionService] 正在上报版本数据到后端: $url');
      debugPrint('[VersionService] 共 ${appVersionHistory.length} 个版本待同步');

      final requestBody = json.encode({
        'versions': appVersionHistory.map((v) => v.toJson()).toList(),
        'sync_time': DateTime.now().toIso8601String(),
        'source': 'app_builtin',
      });

      final response = await _authenticatedRequest(
        method: 'POST',
        url: url,
        token: authToken,
        body: requestBody,
      );

      debugPrint('[VersionService] 同步响应: HTTP ${response.statusCode}');
      debugPrint('[VersionService] 响应体: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = json.decode(response.body);
        if (body['code'] == 200) {
          final data = body['data'] as Map<String, dynamic>?;
          _lastSyncTime = DateTime.now();
          notifyListeners();

          final total = data?['total'] ?? 0;
          final created = data?['created'] ?? 0;
          final skipped = data?['skipped'] ?? 0;
          return (
            success: true,
            message: '同步完成：共 $total 个版本，新增 $created，跳过 $skipped',
          );
        }
        return (
          success: false,
          message: '后端返回错误: ${body['msg'] ?? '未知错误'} (code: ${body['code']})',
        );
      }

      // 解析错误响应
      String errorMsg;
      try {
        final body = json.decode(response.body);
        errorMsg = body['msg'] ?? '未知错误';
      } catch (_) {
        errorMsg = response.body;
      }

      switch (response.statusCode) {
        case 401:
          return (success: false, message: '认证失败: Token 无效或已过期，请重新登录 ($errorMsg)');
        case 403:
          return (success: false, message: '权限不足: X-App-Key 无效或无权限 ($errorMsg)');
        case 404:
          return (success: false, message: '接口不存在: 后端可能尚未部署版本管理模块');
        case 500:
          return (success: false, message: '服务器内部错误: $errorMsg');
        default:
          return (success: false, message: 'HTTP ${ response.statusCode}: $errorMsg');
      }
    } catch (e) {
      debugPrint('[VersionService] 上报异常: $e');
      if (e.toString().contains('TimeoutException')) {
        return (success: false, message: '请求超时，请检查网络连接');
      }
      return (success: false, message: '网络异常: $e');
    }
  }

  /// 上报单个版本到后端
  /// POST /api/v1/app/versions
  Future<({bool success, String message})> reportVersion(String authToken, AppVersion version) async {
    try {
      final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions';
      final response = await _authenticatedRequest(
        method: 'POST',
        url: url,
        token: authToken,
        body: json.encode(version.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = json.decode(response.body);
        if (body['code'] == 200) {
          return (success: true, message: '版本 ${version.version} 上报成功');
        }
        return (success: false, message: '上报失败: ${body['msg'] ?? '未知错误'}');
      }

      return (success: false, message: 'HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[VersionService] 上报单个版本失败: $e');
      return (success: false, message: '网络异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 数据合并
  // ═══════════════════════════════════════════════════════

  /// 合并本地和远程版本数据（去重，以远程为准）
  void _mergeVersions(List<AppVersion> remoteVersions) {
    final Map<String, AppVersion> versionMap = {};

    // 先放本地数据
    for (final v in appVersionHistory) {
      versionMap[v.version] = v;
    }

    // 远程数据覆盖（远程可能有后台手动添加的版本）
    for (final v in remoteVersions) {
      versionMap[v.version] = v;
    }

    // 按版本号倒序排列
    _versions = versionMap.values.toList()
      ..sort((a, b) => _compareVersionStrings(b.version, a.version));
  }

  /// 版本号比较
  int _compareVersionStrings(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  /// 导出所有版本数据为 JSON（供后端批量导入）
  String exportAsJson() {
    final data = {
      'app_name': '途正英语',
      'developer': '火鹰科技',
      'export_time': DateTime.now().toIso8601String(),
      'versions': getAllVersions().map((v) => v.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
