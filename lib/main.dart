/// 途正英语 - 智慧教学管理系统（Flutter多端版）
/// 火鹰科技出品
///
/// 支持平台：iOS / Android / macOS / Windows / Web
/// 一套代码，全端一致
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'pages/main_scaffold.dart';
import 'pages/auth/login_page.dart';
import 'services/im_service.dart';
import 'services/auth_service.dart';
import 'services/conversation_service.dart';
import 'services/chat_message_service.dart';
import 'services/user_info_service.dart';
import 'services/test_service.dart';
import 'services/device_service.dart';

/// 自定义 ScrollBehavior，确保所有平台（含 iOS/Web）都能正常滚动
class TZScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // IM SDK 不在启动时初始化，改为延迟加载（登录成功后或进入聊天时触发）
  // 避免 nim_core_v2 原生 SDK 在 macOS/iOS 上导致 Dart VM 崩溃

  // 尝试自动登录（从本地存储恢复 Token）
  try {
    await AuthService.instance.tryAutoLogin();
  } catch (e) {
    if (kDebugMode) {
      print('[TZ] 自动登录异常: $e');
    }
  }

  runApp(const TZIeltsApp());
}

class TZIeltsApp extends StatelessWidget {
  const TZIeltsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: IMService.instance),
        ChangeNotifierProvider.value(value: AuthService.instance),
        ChangeNotifierProvider.value(value: TZConversationService.instance),
        ChangeNotifierProvider.value(value: ChatMessageService.instance),
        ChangeNotifierProvider.value(value: UserInfoService.instance),
        ChangeNotifierProvider.value(value: TestService.instance),
      ],
      child: MaterialApp(
        title: '途正英语',
        debugShowCheckedModeBanner: false,
        theme: TZTheme.lightTheme,
        scrollBehavior: TZScrollBehavior(),
        home: const _AuthGate(),
      ),
    );
  }
}

/// 认证网关：根据登录状态决定显示登录页还是主页面
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (auth.isLoggedIn) {
          return const MainScaffold();
        }
        return LoginPage(
          onLoginSuccess: () {
            // 登录成功后 AuthService.isLoggedIn 变为 true，
            // Consumer 会自动重建，切换到 MainScaffold
          },
        );
      },
    );
  }
}
