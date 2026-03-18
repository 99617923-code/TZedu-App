/// 途正英语 - 聊天列表项卡片
/// 火鹰科技出品
///
/// 根据聊天类型渲染不同样式的卡片：
/// direct(私聊)、group(群聊)、feature(功能空间)、
/// activity(活动)、homework(作业)、notification(通知)
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/chat_data.dart';

class ChatItemCard extends StatelessWidget {
  final ChatItem chat;
  final bool isSelected;
  final VoidCallback onTap;

  const ChatItemCard({
    super.key,
    required this.chat,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: isSelected
              ? const Border(
                  left: BorderSide(color: Color(0xFF7C3AED), width: 3),
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 左侧类型指示条（非选中状态）
            if (!isSelected)
              Positioned(
                left: 0,
                top: 8,
                bottom: 8,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: getTypeColor(chat.type),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            // 置顶标识
            if (chat.pinned)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.push_pin,
                  size: 12,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            // 内容
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (chat.type) {
      case ChatItemType.direct:
        return _buildDirectCard();
      case ChatItemType.group:
        return _buildGroupCard();
      case ChatItemType.feature:
        return _buildFeatureCard();
      case ChatItemType.activity:
        return _buildActivityCard();
      case ChatItemType.homework:
        return _buildHomeworkCard();
      case ChatItemType.notification:
        return _buildNotificationCard();
    }
  }

  // ═══ 私聊卡片 ═══
  Widget _buildDirectCard() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // 头像 + 在线状态
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildAvatar(chat.avatar, 48),
              if (chat.isOnline)
                Positioned(
                  bottom: -1,
                  right: -1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              if (chat.nationality != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Text(chat.nationality!, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 名称 + 最后消息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chat.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (chat.tags.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _buildTag(chat.tags.first, const Color(0xFF065F46), const Color(0xFFF0FDF4)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  chat.subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 时间 + 未读
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                chat.lastTime,
                style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
              if (chat.unread > 0) ...[
                const SizedBox(height: 4),
                _buildUnreadBadge(chat.unread, const Color(0xFFEF4444)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 群聊卡片 ═══
  Widget _buildGroupCard() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: Text('👥', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chat.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (chat.memberCount != null) ...[
                      const SizedBox(width: 6),
                      _buildTag('${chat.memberCount}人', const Color(0xFF1D4ED8), const Color(0xFFEFF6FF)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  chat.subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(chat.lastTime, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
              if (chat.unread > 0) ...[
                const SizedBox(height: 4),
                _buildUnreadBadge(chat.unread, const Color(0xFF3B82F6)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 功能空间卡片 ═══
  Widget _buildFeatureCard() {
    final iconData = getChatItemIcon(chat);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconData.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(iconData.icon, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...chat.tags.take(2).map((tag) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _buildTag(tag, iconData.color, iconData.color.withOpacity(0.1)),
                        )),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chat.subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(chat.lastTime, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                  if (chat.unread > 0) ...[
                    const SizedBox(height: 4),
                    _buildUnreadBadge(chat.unread, iconData.color),
                  ],
                ],
              ),
            ],
          ),
          if (chat.featureDesc != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 60),
              child: Text(
                chat.featureDesc!,
                style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══ 活动卡片 ═══
  Widget _buildActivityCard() {
    final iconData = getChatItemIcon(chat);
    final status = getActivityStatusLabel(chat.activityStatus);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconData.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(iconData.icon, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      chat.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: status.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.text,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  chat.subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (chat.activityTime != null)
                      Text(
                        '🕐 ${chat.activityTime}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: iconData.color),
                      ),
                    if (chat.participantCount != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '👤 ${chat.participantCount}人',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (chat.unread > 0) _buildUnreadBadge(chat.unread, iconData.color),
              const SizedBox(height: 4),
              const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD1D5DB)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 作业卡片 ═══
  Widget _buildHomeworkCard() {
    final Map<HomeworkStatus, ({String icon, Color color, Color bg, String label})> statusConfig = {
      HomeworkStatus.pending: (icon: '✏️', color: const Color(0xFFD97706), bg: const Color(0xFFFEF3C7), label: '待完成'),
      HomeworkStatus.submitted: (icon: '✅', color: const Color(0xFF059669), bg: const Color(0xFFD1FAE5), label: '已提交'),
      HomeworkStatus.graded: (icon: '📊', color: const Color(0xFF7C3AED), bg: const Color(0xFFEDE9FE), label: '已批改'),
    };
    final status = statusConfig[chat.homeworkStatus ?? HomeworkStatus.pending]!;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: status.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(status.icon, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chat.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: status.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  chat.subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
                if (chat.homeworkDeadline != null && chat.homeworkStatus == HomeworkStatus.pending) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⭐ 截止: ${chat.homeworkDeadline}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(chat.lastTime, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
              if (chat.unread > 0) ...[
                const SizedBox(height: 4),
                _buildUnreadBadge(chat.unread, status.color),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 通知卡片 ═══
  Widget _buildNotificationCard() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: Text('🔔', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chat.subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(chat.lastTime, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
              if (chat.unread > 0) ...[
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══ 通用组件 ═══

  Widget _buildAvatar(String url, double size) {
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Center(
          child: Text(
            chat.name.isNotEmpty ? chat.name[0] : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.5),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.person, color: Color(0xFF9CA3AF)),
        ),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.person, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildUnreadBadge(int count, Color color) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
