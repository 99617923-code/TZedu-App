/// 途正英语 - 网易云信 IM 配置
/// 火鹰科技出品
///
/// 集中管理网易云信 SDK 的配置参数
/// AppKey 优先从后端接口动态获取，本地仅作为 fallback

class IMConfig {
  /// 网易云信 AppKey
  /// 优先使用后端接口返回的 app_key（im_auth.app_key）
  /// 此处仅作为后端未返回时的 fallback
  static String _appKey = '';

  /// 获取 AppKey（优先后端下发值）
  static String get appKey => _appKey;

  /// 由 AuthService 在登录成功后设置后端下发的 AppKey
  static void setAppKey(String key) {
    if (key.isNotEmpty) {
      _appKey = key;
    }
  }

  /// 后端 API 基础地址
  static const String apiBaseUrl = 'https://tzapp-admin.figo.cn';

  /// 登录接口路径
  static const String loginPath = '/api/v1/auth/login';

  /// 获取当前用户信息接口路径
  static const String mePath = '/api/v1/auth/me';

  /// 刷新 Token 接口路径
  static const String refreshTokenPath = '/api/v1/auth/refresh-token';

  /// 登出接口路径
  static const String logoutPath = '/api/v1/auth/logout';

  /// 更新用户资料接口路径
  static const String updateProfilePath = '/api/v1/user/profile';

  /// IM 连接超时时间（秒）
  static const int connectTimeout = 30;

  /// 消息漫游天数
  static const int messageRoamingDays = 7;

  /// 是否启用调试日志
  static const bool enableDebugLog = true;
}
