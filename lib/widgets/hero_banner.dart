/// 途正英语 - Hero Banner 组件
/// 火鹰科技出品
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/constants.dart';
import '../models/app_role.dart';

class HeroBanner extends StatelessWidget {
  final AppRole role;

  const HeroBanner({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final height = isWide ? 176.0 : 144.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B3486).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图片
          CachedNetworkImage(
            imageUrl: AppImages.heroBanner,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B3486), Color(0xFF7C3AED)],
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B3486), Color(0xFF7C3AED)],
                ),
              ),
            ),
          ),

          // 渐变遮罩
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF3B3486).withOpacity(0.6),
                  const Color(0xFF7C3AED).withOpacity(0.4),
                  const Color(0xFF3B3486).withOpacity(0.3),
                ],
              ),
            ),
          ),

          // 左下文字
          Positioned(
            bottom: 16,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '途正英语',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role.bannerSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),

          // 右上标签
          Positioned(
            top: 12,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Text(
                'IELTS 5.5 - 9.0',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
