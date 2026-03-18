/// 途正英语 - 角色模型
/// 火鹰科技出品
import 'package:flutter/material.dart';
import '../config/theme.dart';

enum AppRole {
  student,
  teacher,
  parent,
}

extension AppRoleExtension on AppRole {
  String get label {
    switch (this) {
      case AppRole.student:
        return '学生';
      case AppRole.teacher:
        return '老师';
      case AppRole.parent:
        return '家长';
    }
  }

  String get endLabel {
    switch (this) {
      case AppRole.student:
        return '学生端';
      case AppRole.teacher:
        return '老师端';
      case AppRole.parent:
        return '家长端';
    }
  }

  String get bannerSubtitle {
    switch (this) {
      case AppRole.student:
        return 'Ace your IELTS with us! 🚀';
      case AppRole.teacher:
        return 'Ready to inspire your students today!';
      case AppRole.parent:
        return "Stay connected with your child's progress!";
    }
  }

  String get userName {
    switch (this) {
      case AppRole.student:
        return 'Lily Zhang';
      case AppRole.teacher:
        return 'Sarah Wang';
      case AppRole.parent:
        return 'Lily Zhang';
    }
  }

  String get displayName {
    switch (this) {
      case AppRole.student:
        return 'Lily Zhang';
      case AppRole.teacher:
        return 'Sarah Wang';
      case AppRole.parent:
        return 'Lily Zhang家长';
    }
  }

  List<Color> get gradient {
    switch (this) {
      case AppRole.student:
        return TZColors.studentGradient;
      case AppRole.teacher:
        return TZColors.teacherGradient;
      case AppRole.parent:
        return TZColors.parentGradient;
    }
  }

  Color get shadowColor {
    switch (this) {
      case AppRole.student:
        return TZColors.red.withOpacity(0.3);
      case AppRole.teacher:
        return TZColors.primaryPurple.withOpacity(0.3);
      case AppRole.parent:
        return TZColors.orange.withOpacity(0.3);
    }
  }
}
