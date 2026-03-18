/// 途正英语 - 主题配置
/// 火鹰科技出品
import 'package:flutter/material.dart';

class TZColors {
  // 主色调
  static const Color primaryPurple = Color(0xFF7C3AED);
  static const Color deepPurple = Color(0xFF3B3486);
  static const Color lightPurple = Color(0xFF8B5CF6);
  static const Color indigo = Color(0xFF6366F1);

  // 功能色
  static const Color orange = Color(0xFFF59E0B);
  static const Color darkOrange = Color(0xFFD97706);
  static const Color deepOrange = Color(0xFFEF6C00);
  static const Color red = Color(0xFFFF6B6B);
  static const Color darkRed = Color(0xFFDC2626);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color green = Color(0xFF059669);
  static const Color lightGreen = Color(0xFF10B981);
  static const Color blue = Color(0xFF3B82F6);
  static const Color deepBlue = Color(0xFF4338CA);
  static const Color pink = Color(0xFFEC4899);

  // 文字色
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textGray = Color(0xFF6B7280);
  static const Color textMedium = Color(0xFF374151);
  static const Color textLight = Color(0xFF9CA3AF);

  // 背景色
  static const Color bgStart = Color(0xFFF5F3FF);
  static const Color bgPurple = Color(0xFFEDE9FE);
  static const Color bgMid = Color(0xFFF8F7FF);
  static const Color bgEnd = Color(0xFFF9FAFB);

  // 角色渐变
  static const List<Color> studentGradient = [Color(0xFFFF6B6B), Color(0xFFF59E0B)];
  static const List<Color> teacherGradient = [Color(0xFF3B3486), Color(0xFF7C3AED)];
  static const List<Color> parentGradient = [Color(0xFFF59E0B), Color(0xFFEF6C00)];
  static const List<Color> aiGradient = [Color(0xFF8B5CF6), Color(0xFF6366F1)];
}

class TZTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TZColors.primaryPurple,
        brightness: Brightness.light,
      ),
      fontFamily: 'PingFang SC',
      scaffoldBackgroundColor: TZColors.bgStart,
    );
  }
}
