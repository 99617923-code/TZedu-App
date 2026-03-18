/// 途正英语 - 网易云信 IM 配置
/// 火鹰科技出品
///
/// 集中管理网易云信 SDK 的配置参数
/// 注意：AppKey 等敏感信息后续应从后端获取或通过环境变量注入

class IMConfig {
  /// 网易云信 AppKey（需替换为实际值）
  /// 在 https://app.yunxin.163.com 控制台获取
  static const String appKey = 'YOUR_APP_KEY_HERE';

  /// 后端 API 基础地址（用于获取 IM Token）
  static const String apiBaseUrl = 'https://api.tuzheng.com';

  /// 登录接口路径
  static const String loginPath = '/api/v1/auth/login';

  /// 刷新 Token 接口路径
  static const String refreshTokenPath = '/api/v1/auth/refresh-token';

  /// IM 连接超时时间（秒）
  static const int connectTimeout = 30;

  /// 消息漫游天数
  static const int messageRoamingDays = 7;

  /// 是否启用调试日志
  static const bool enableDebugLog = true;
}
