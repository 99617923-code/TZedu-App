/// 途正英语 - 智慧教学管理系统（Flutter多端版）
/// 火鹰科技出品
///
/// 支持平台：iOS / Android / macOS / Windows / Web
/// 一套代码，全端一致
import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'pages/home_page.dart';

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
      home: const HomePage(),
    );
  }
}
