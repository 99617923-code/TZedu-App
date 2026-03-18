/// 途正英语 - 首页数据模型
/// 火鹰科技出品
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import 'app_role.dart';

class FeatureCardData {
  final String image;
  final String title;
  final String desc;
  final String? badge;
  final Color? badgeColor;
  final Color accentColor;
  final bool isLarge;
  final bool aiEnabled;

  const FeatureCardData({
    required this.image,
    required this.title,
    required this.desc,
    this.badge,
    this.badgeColor,
    required this.accentColor,
    this.isLarge = false,
    this.aiEnabled = false,
  });
}

class QuickEntryData {
  final IconData icon;
  final String label;
  final Color accentColor;
  final bool aiEnabled;

  const QuickEntryData({
    required this.icon,
    required this.label,
    required this.accentColor,
    this.aiEnabled = false,
  });
}

class HomeDataProvider {
  static List<FeatureCardData> getFeatures(AppRole role) {
    switch (role) {
      case AppRole.teacher:
        return [
          FeatureCardData(
            image: AppImages.featureHomework,
            title: '作业管理',
            desc: '真实老师批改，AI加持',
            accentColor: TZColors.darkOrange,
            badge: '核心',
            badgeColor: TZColors.orange,
            isLarge: true,
            aiEnabled: true,
          ),
          FeatureCardData(
            image: AppImages.liveClassHero1,
            title: '外教直播',
            desc: '真人外教，AI加持',
            accentColor: TZColors.primaryPurple,
            badge: 'LIVE',
            badgeColor: TZColors.errorRed,
            aiEnabled: true,
          ),
          FeatureCardData(
            image: AppImages.featureAttendance,
            title: '课程点名',
            desc: '出勤记录 · 到课统计',
            accentColor: TZColors.green,
          ),
        ];
      case AppRole.student:
        return [
          FeatureCardData(
            image: AppImages.featureStudentLearn,
            title: '我的作业',
            desc: '真实老师批改，AI加持',
            accentColor: TZColors.darkRed,
            badge: '待完成 3',
            badgeColor: TZColors.errorRed,
            isLarge: true,
            aiEnabled: true,
          ),
          FeatureCardData(
            image: AppImages.liveClassHero2,
            title: '外教直播',
            desc: '真人外教，AI加持',
            accentColor: TZColors.primaryPurple,
            badge: 'LIVE',
            badgeColor: TZColors.errorRed,
            aiEnabled: true,
          ),
          FeatureCardData(
            image: AppImages.featureSchedule,
            title: '课程排期',
            desc: '我的课表 · 上课提醒',
            accentColor: TZColors.deepBlue,
          ),
        ];
      case AppRole.parent:
        return [
          FeatureCardData(
            image: AppImages.featureStudentLearn,
            title: '学习概览',
            desc: '孩子学习情况 · AI分析 · 成绩趋势',
            accentColor: TZColors.darkOrange,
            badge: '今日',
            badgeColor: TZColors.orange,
            isLarge: true,
            aiEnabled: true,
          ),
          FeatureCardData(
            image: AppImages.featureSchedule,
            title: '课程排期',
            desc: '孩子课表 · 上课提醒',
            accentColor: TZColors.deepBlue,
          ),
          FeatureCardData(
            image: AppImages.featureHomework,
            title: '作业情况',
            desc: '作业完成 · 老师评价',
            accentColor: TZColors.darkRed,
          ),
        ];
    }
  }

  static List<QuickEntryData> getQuickEntries(AppRole role) {
    switch (role) {
      case AppRole.teacher:
        return [
          QuickEntryData(icon: Icons.people_outline, label: '班级管理', accentColor: TZColors.deepPurple),
          QuickEntryData(icon: Icons.calendar_month_outlined, label: '课程排期', accentColor: TZColors.primaryPurple),
          QuickEntryData(icon: Icons.edit_note, label: '批改作业', accentColor: TZColors.orange, aiEnabled: true),
          QuickEntryData(icon: Icons.library_books_outlined, label: '作业列表', accentColor: TZColors.blue),
          QuickEntryData(icon: Icons.description_outlined, label: '课件制作', accentColor: TZColors.lightPurple),
          QuickEntryData(icon: Icons.menu_book_outlined, label: '课程教材', accentColor: TZColors.green),
          QuickEntryData(icon: Icons.chat_bubble_outline, label: '消息聊天', accentColor: TZColors.pink),
          QuickEntryData(icon: Icons.person_outline, label: '个人中心', accentColor: TZColors.indigo),
        ];
      case AppRole.student:
        return [
          QuickEntryData(icon: Icons.play_circle_outline, label: '视频课程', accentColor: TZColors.pink),
          QuickEntryData(icon: Icons.people_outline, label: '我的班级', accentColor: TZColors.deepPurple),
          QuickEntryData(icon: Icons.edit_note, label: '批改结果', accentColor: TZColors.orange, aiEnabled: true),
          QuickEntryData(icon: Icons.calendar_month_outlined, label: '约课', accentColor: TZColors.blue),
          QuickEntryData(icon: Icons.access_time, label: '我的课时', accentColor: TZColors.green),
          QuickEntryData(icon: Icons.menu_book_outlined, label: '课程教材', accentColor: TZColors.lightGreen),
          QuickEntryData(icon: Icons.chat_bubble_outline, label: '消息聊天', accentColor: TZColors.pink),
          QuickEntryData(icon: Icons.person_outline, label: '个人中心', accentColor: TZColors.indigo),
        ];
      case AppRole.parent:
        return [
          QuickEntryData(icon: Icons.school_outlined, label: '成绩趋势', accentColor: TZColors.lightGreen),
          QuickEntryData(icon: Icons.play_circle_outline, label: '视频课程', accentColor: TZColors.pink),
          QuickEntryData(icon: Icons.people_outline, label: '班级信息', accentColor: TZColors.deepPurple),
          QuickEntryData(icon: Icons.calendar_month_outlined, label: '约课', accentColor: TZColors.blue),
          QuickEntryData(icon: Icons.access_time, label: '课时查询', accentColor: TZColors.green),
          QuickEntryData(icon: Icons.chat_bubble_outline, label: '消息聊天', accentColor: TZColors.pink),
          QuickEntryData(icon: Icons.person_outline, label: '个人中心', accentColor: TZColors.indigo),
        ];
    }
  }
}
