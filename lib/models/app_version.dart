/// 途正英语 - 版本数据模型
/// 火鹰科技出品
///
/// 用于版本管理页面展示和后端 API 数据交换
/// 支持 JSON 序列化/反序列化，便于前后端数据同步

class AppVersion {
  /// 版本号（语义化版本: x.y.z）
  final String version;

  /// 构建号
  final String buildNumber;

  /// 版本类型: major / minor / patch / hotfix
  final String type;

  /// 发布日期（ISO 8601 格式: yyyy-MM-dd）
  final String releaseDate;

  /// 版本标题（简短描述）
  final String title;

  /// 版本描述（详细说明）
  final String description;

  /// 更新内容列表
  final List<ChangelogEntry> changes;

  /// 是否为强制更新
  final bool forceUpdate;

  /// 支持的平台列表
  final List<String> platforms;

  /// 最低支持版本（低于此版本必须更新）
  final String? minSupportedVersion;

  /// 下载链接（各平台）
  final Map<String, String>? downloadUrls;

  /// Git commit hash
  final String? commitHash;

  /// 开发者
  final String developer;

  const AppVersion({
    required this.version,
    required this.buildNumber,
    required this.type,
    required this.releaseDate,
    required this.title,
    required this.description,
    required this.changes,
    this.forceUpdate = false,
    this.platforms = const ['android', 'ios', 'macos', 'windows', 'web'],
    this.minSupportedVersion,
    this.downloadUrls,
    this.commitHash,
    this.developer = '火鹰科技',
  });

  /// 从 JSON 反序列化
  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] ?? '',
      buildNumber: json['build_number']?.toString() ?? '1',
      type: json['type'] ?? 'patch',
      releaseDate: json['release_date'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      changes: (json['changes'] as List<dynamic>?)
              ?.map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      forceUpdate: json['force_update'] ?? false,
      platforms: (json['platforms'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['android', 'ios', 'macos', 'windows', 'web'],
      minSupportedVersion: json['min_supported_version'],
      downloadUrls: (json['download_urls'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      commitHash: json['commit_hash'],
      developer: json['developer'] ?? '火鹰科技',
    );
  }

  /// 序列化为 JSON（用于上报给后端）
  Map<String, dynamic> toJson() => {
        'version': version,
        'build_number': buildNumber,
        'type': type,
        'release_date': releaseDate,
        'title': title,
        'description': description,
        'changes': changes.map((e) => e.toJson()).toList(),
        'force_update': forceUpdate,
        'platforms': platforms,
        if (minSupportedVersion != null)
          'min_supported_version': minSupportedVersion,
        if (downloadUrls != null) 'download_urls': downloadUrls,
        if (commitHash != null) 'commit_hash': commitHash,
        'developer': developer,
      };

  /// 获取版本类型标签
  String get typeLabel {
    switch (type) {
      case 'major':
        return '重大更新';
      case 'minor':
        return '功能更新';
      case 'patch':
        return '问题修复';
      case 'hotfix':
        return '紧急修复';
      default:
        return '更新';
    }
  }

  /// 统计各类变更数量
  int get featCount =>
      changes.where((c) => c.category == 'feat').length;
  int get fixCount =>
      changes.where((c) => c.category == 'fix').length;
  int get improveCount =>
      changes.where((c) => c.category == 'improve').length;
}

/// 单条变更记录
class ChangelogEntry {
  /// 变更类别: feat / fix / improve / docs / chore
  final String category;

  /// 变更描述
  final String content;

  /// 影响模块
  final String? module;

  /// 关联的 commit hash
  final String? commitHash;

  const ChangelogEntry({
    required this.category,
    required this.content,
    this.module,
    this.commitHash,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    return ChangelogEntry(
      category: json['category'] ?? 'feat',
      content: json['content'] ?? '',
      module: json['module'],
      commitHash: json['commit_hash'],
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'content': content,
        if (module != null) 'module': module,
        if (commitHash != null) 'commit_hash': commitHash,
      };

  /// 获取类别标签
  String get categoryLabel {
    switch (category) {
      case 'feat':
        return '新功能';
      case 'fix':
        return '修复';
      case 'improve':
        return '优化';
      case 'docs':
        return '文档';
      case 'chore':
        return '维护';
      default:
        return '其他';
    }
  }
}
