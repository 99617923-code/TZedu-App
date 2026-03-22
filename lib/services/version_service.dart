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
    if (authToken != null) {
      try {
        final remoteVersions = await _fetchRemoteVersions(authToken);
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

  /// 从后端拉取版本列表
  /// GET /api/v1/app/versions
  Future<List<AppVersion>> _fetchRemoteVersions(String authToken) async {
    final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions';
    debugPrint('[VersionService] 正在从后端拉取版本数据: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: IMConfig.authHeaders(authToken),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      final data = body['data'] as List<dynamic>? ?? [];
      return data
          .map((e) => AppVersion.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    debugPrint('[VersionService] 后端返回: ${response.statusCode}');
    return [];
  }

  /// 上报本地版本数据到后端（管理员操作）
  /// POST /api/v1/app/versions/sync
  Future<bool> syncToBackend(String authToken) async {
    try {
      final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions/sync';
      debugPrint('[VersionService] 正在上报版本数据到后端: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: IMConfig.authHeaders(authToken),
        body: json.encode({
          'versions': appVersionHistory.map((v) => v.toJson()).toList(),
          'sync_time': DateTime.now().toIso8601String(),
          'source': 'app_builtin',
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _lastSyncTime = DateTime.now();
        notifyListeners();
        return true;
      }

      debugPrint('[VersionService] 上报失败: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[VersionService] 上报异常: $e');
      return false;
    }
  }

  /// 上报单个版本到后端
  /// POST /api/v1/app/versions
  Future<bool> reportVersion(String authToken, AppVersion version) async {
    try {
      final url = '${IMConfig.apiBaseUrl}/api/v1/app/versions';
      final response = await http.post(
        Uri.parse(url),
        headers: IMConfig.authHeaders(authToken),
        body: json.encode(version.toJson()),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[VersionService] 上报单个版本失败: $e');
      return false;
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
