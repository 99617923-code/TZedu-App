/// 途正英语 - IM 及后端 API 配置
/// 火鹰科技出品
///
/// 集中管理网易云信 SDK 配置参数和后端 API 路径
/// AppKey 优先从后端接口动态获取，本地仅作为 fallback

class IMConfig {
  // ═══════════════════════════════════════════════════════
  // 网易云信 AppKey
  // ═══════════════════════════════════════════════════════

  /// 网易云信 AppKey（后端下发优先，此处为 fallback）
  static String _appKey = '778711d27ade8e02095f8589a28344a2';

  /// 获取 AppKey（优先后端下发值）
  static String get appKey => _appKey;

  /// 由 AuthService 在登录成功后设置后端下发的 AppKey
  static void setAppKey(String key) {
    if (key.isNotEmpty) {
      _appKey = key;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 后端 API 配置
  // ═══════════════════════════════════════════════════════

  /// 后端 API 基础地址
  static const String apiBaseUrl = 'https://tzapp-admin.figo.cn';

  /// 途正开放平台 X-App-Key（每次请求必带）
  static const String xAppKey = 'tzk_bd63c64497ed26fd9f197758a489be6f';

  // ═══════════════════════════════════════════════════════
  // 认证接口
  // ═══════════════════════════════════════════════════════

  /// 获取图形验证码
  static const String captchaPath = '/api/v1/auth/captcha';

  /// 发送短信验证码
  static const String sendSmsCodePath = '/api/v1/auth/send-sms-code';

  /// 用户注册
  static const String registerPath = '/api/v1/auth/register';

  /// 用户登录（密码登录）
  static const String loginPath = '/api/v1/auth/login';

  /// 短信验证码登录
  static const String smsLoginPath = '/api/v1/auth/sms-login';

  /// 获取当前用户信息
  static const String mePath = '/api/v1/auth/me';

  /// 刷新 Token
  static const String refreshTokenPath = '/api/v1/auth/refresh-token';

  /// 登出
  static const String logoutPath = '/api/v1/auth/logout';

  // ═══════════════════════════════════════════════════════
  // 用户接口
  // ═══════════════════════════════════════════════════════

  /// 更新用户资料
  static const String updateProfilePath = '/api/v1/user/profile';

  // ═══════════════════════════════════════════════════════
  // 设备管理接口
  // ═══════════════════════════════════════════════════════

  /// 设备注册
  static const String deviceRegisterPath = '/api/v1/device/register';

  /// 设备心跳
  static const String deviceHeartbeatPath = '/api/v1/device/heartbeat';

  /// 更新推送 Token
  static const String devicePushTokenPath = '/api/v1/device/push-token';

  // ═══════════════════════════════════════════════════════
  // AI 测评接口
  // ═══════════════════════════════════════════════════════

  /// 创建测评会话
  static const String testStartPath = '/api/v1/test/start';

  /// 提交评估
  static const String testEvaluatePath = '/api/v1/test/evaluate';

  /// 获取测评结果
  static const String testResultPath = '/api/v1/test/result'; // + /:sessionId

  /// 测评历史
  static const String testHistoryPath = '/api/v1/test/history';

  /// 文本转语音
  static const String testTtsPath = '/api/v1/test/tts';

  // ═══════════════════════════════════════════════════════
  // IM 参数
  // ═══════════════════════════════════════════════════════

  /// IM 连接超时时间（秒）
  static const int connectTimeout = 30;

  /// 消息漫游天数
  static const int messageRoamingDays = 7;

  /// 是否启用调试日志
  static const bool enableDebugLog = true;

  // ═══════════════════════════════════════════════════════
  // 通用 HTTP Headers
  // ═══════════════════════════════════════════════════════

  /// 获取基础请求头（不含 Authorization）
  static Map<String, String> get baseHeaders => {
    'Content-Type': 'application/json',
    'X-App-Key': xAppKey,
  };

  /// 获取带认证的请求头
  static Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'X-App-Key': xAppKey,
    'Authorization': 'Bearer $token',
  };
}
