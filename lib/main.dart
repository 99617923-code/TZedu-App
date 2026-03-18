/// 途正英语 - 智慧教学管理系统（Flutter多端版）
/// 火鹰科技出品
///
/// 支持平台：iOS / Android / macOS / Windows / Web
/// 一套代码，全端一致
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'config/theme.dart';
import 'pages/main_scaffold.dart';

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TZIeltsApp());
}

class TZIeltsApp extends StatelessWidget {
  const TZIeltsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '途正英语',
      debugShowCheckedModeBanner: false,
      theme: TZTheme.lightTheme,
      scrollBehavior: TZScrollBehavior(),
      home: const MainScaffold(),
    );
  }
}
