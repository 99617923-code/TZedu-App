/// 途正英语 - 应用内消息通知服务
/// 火鹰科技出品
///
/// 职责：
/// 1. 收到新消息时在 App 内显示横幅通知
/// 2. 播放消息提示音
/// 3. 管理通知显示状态（当前聊天页面不弹通知）
///
/// 使用方式：
///   NotificationService.instance.initialize(navigatorKey);
///   NotificationService.instance.showInAppNotification(senderName, message);

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_message_service.dart';
import 'conversation_service.dart';
import 'user_info_service.dart';
import 'im_service.dart';

class NotificationService {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;
  NotificationService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  GlobalKey<NavigatorState>? _navigatorKey;
  OverlayEntry? _currentNotification;
  Timer? _autoDismissTimer;
  StreamSubscription<List<TZMessage>>? _messageSub;

  /// 当前正在查看的会话 ID（在此会话中不弹通知）
  String? _activeConversationId;

  /// 设置当前活跃的会话（进入聊天页面时调用）
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  // ═══════════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════════

  /// 初始化通知服务（在 MaterialApp 创建后调用）
  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _setupMessageListener();
    _log('通知服务已初始化');
  }

  /// 监听新消息，自动弹出通知
  void _setupMessageListener() {
    _messageSub?.cancel();
    _messageSub = ChatMessageService.instance.messageStream.listen((messages) {
      for (final msg in messages) {
        // 不显示自己发的消息的通知
        if (msg.isMine) continue;

        // 不显示当前正在查看的会话的通知
        if (_activeConversationId != null &&
            msg.conversationId == _activeConversationId) {
          continue;
        }

        // 获取发送者信息
        _showNotificationForMessage(msg);
      }
    });
  }

  /// 为消息显示通知
  Future<void> _showNotificationForMessage(TZMessage msg) async {
    // 尝试获取发送者昵称
    String senderName = msg.senderName;
    if (senderName.isEmpty || senderName == msg.senderId) {
      try {
        final userInfo = await UserInfoService.instance.getUserInfo(msg.senderId);
        if (userInfo != null && userInfo.name.isNotEmpty) {
          senderName = userInfo.name;
        }
      } catch (_) {}
    }
    if (senderName.isEmpty) senderName = msg.senderId;

    // 获取消息预览文本
    String preview;
    switch (msg.type) {
      case TZMessageType.text:
        preview = msg.text;
        break;
      case TZMessageType.image:
        preview = '[图片]';
        break;
      case TZMessageType.audio:
        preview = '[语音]';
        break;
      case TZMessageType.video:
        preview = '[视频]';
        break;
      case TZMessageType.file:
        preview = '[文件]';
        break;
      default:
        preview = '[消息]';
    }

    showInAppNotification(
      senderName: senderName,
      message: preview,
      conversationId: msg.conversationId,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 应用内横幅通知
  // ═══════════════════════════════════════════════════════

  /// 显示应用内横幅通知
  void showInAppNotification({
    required String senderName,
    required String message,
    String? conversationId,
  }) {
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    // 先移除已有通知
    dismissNotification();

    // 播放提示音
    _playNotificationSound();

    _currentNotification = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        senderName: senderName,
        message: message,
        onTap: () {
          dismissNotification();
          if (conversationId != null) {
            _navigateToConversation(conversationId, senderName);
          }
        },
        onDismiss: () => dismissNotification(),
      ),
    );

    overlay.insert(_currentNotification!);

    // 5 秒后自动消失
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 5), () {
      dismissNotification();
    });
  }

  /// 关闭当前通知
  void dismissNotification() {
    _autoDismissTimer?.cancel();
    _currentNotification?.remove();
    _currentNotification = null;
  }

  /// 播放消息提示音
  void _playNotificationSound() {
    try {
      // 使用系统默认提示音
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      _log('播放提示音失败: $e');
    }
  }

  /// 点击通知后跳转到对应会话
  void _navigateToConversation(String conversationId, String senderName) {
    // 通过 NavigatorKey 获取当前 context 并跳转
    // 这里简单处理：设置 activeConversation 并通知 UI 层
    _notificationTapController.add(_NotificationTapEvent(
      conversationId: conversationId,
      senderName: senderName,
    ));
  }

  /// 通知点击事件流（供 UI 层监听并跳转）
  final StreamController<_NotificationTapEvent> _notificationTapController =
      StreamController<_NotificationTapEvent>.broadcast();
  Stream<_NotificationTapEvent> get onNotificationTap =>
      _notificationTapController.stream;

  void _log(String message) {
    debugPrint('[NotificationService] $message');
  }

  void dispose() {
    _messageSub?.cancel();
    _autoDismissTimer?.cancel();
    _currentNotification?.remove();
    _notificationTapController.close();
  }
}

/// 通知点击事件
class _NotificationTapEvent {
  final String conversationId;
  final String senderName;
  _NotificationTapEvent({required this.conversationId, required this.senderName});
}

// ═══════════════════════════════════════════════════════
// 应用内横幅通知 Widget
// ═══════════════════════════════════════════════════════

class _InAppNotificationBanner extends StatefulWidget {
  final String senderName;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.senderName,
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
                widget.onDismiss();
              }
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              shadowColor: const Color(0xFF7C3AED).withOpacity(0.2),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFEDE9FE),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 头像
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          widget.senderName.isNotEmpty
                              ? widget.senderName[0]
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 消息内容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              // App 名称标签
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '途正英语',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF7C3AED),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.senderName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Text(
                                '现在',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
