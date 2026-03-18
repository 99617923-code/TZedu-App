/// 途正英语 - 快捷入口组件
/// 火鹰科技出品
import 'package:flutter/material.dart';
import '../models/home_data.dart';
import '../config/theme.dart';

class QuickEntry extends StatefulWidget {
  final QuickEntryData data;
  final VoidCallback? onTap;

  const QuickEntry({super.key, required this.data, this.onTap});

  @override
  State<QuickEntry> createState() => _QuickEntryState();
}

class _QuickEntryState extends State<QuickEntry> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..translate(0.0, _isHovered ? -2.0 : 0.0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
            boxShadow: _isHovered
                ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.accentColor, size: 18),
              ),
              const SizedBox(width: 12),

              // 标签
              Expanded(
                child: Row(
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: TZColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (data.aiEnabled) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: TZColors.aiGradient),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 9),
                            SizedBox(width: 2),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 箭头
              Icon(
                Icons.chevron_right,
                color: TZColors.textGray.withOpacity(_isHovered ? 0.6 : 0.3),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
