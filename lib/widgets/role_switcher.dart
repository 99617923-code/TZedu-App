/// 途正英语 - 角色切换组件
/// 火鹰科技出品
import 'package:flutter/material.dart';
import '../models/app_role.dart';

class RoleSwitcher extends StatelessWidget {
  final AppRole currentRole;
  final ValueChanged<AppRole> onRoleChanged;

  const RoleSwitcher({
    super.key,
    required this.currentRole,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppRole.values.map((role) {
          final isActive = role == currentRole;
          return GestureDetector(
            onTap: () => onRoleChanged(role),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: role.gradient,
                      )
                    : null,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isActive
                    ? [BoxShadow(color: role.shadowColor, blurRadius: 8, offset: const Offset(0, 2))]
                    : [],
              ),
              child: Text(
                role.label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey[400],
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
