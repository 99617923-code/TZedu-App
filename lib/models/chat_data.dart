/// 途正英语 - 社交聊天系统数据模型（对标HelloTalk）
/// 火鹰科技出品
///
/// 支持：单聊、群聊、功能空间、活动空间、作业通知
/// 特色：AI教练自动评分英文表达
/// 安全：违禁词过滤、二维码屏蔽
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════
// 枚举类型
// ═══════════════════════════════════════════════════════

/// 聊天项类型
enum ChatItemType { direct, group, feature, activity, homework, notification }

/// 消息类型
enum MessageType { text, voice, image, aiCoach, system, correction }

/// 消息发送者角色
enum SenderRole { student, teacher, foreignTeacher, ai, system }

/// 活动状态
enum ActivityStatus { upcoming, ongoing, ended }

/// 作业状态
enum HomeworkStatus { pending, submitted, graded }

// ═══════════════════════════════════════════════════════
// AI 教练评分模型
// ═══════════════════════════════════════════════════════

class GrammarAnalysis {
  final int score;
  final List<String> issues;

  const GrammarAnalysis({required this.score, required this.issues});
}

class VocabularyAnalysis {
  final int score;
  final String level;

  const VocabularyAnalysis({required this.score, required this.level});
}

class ExpressionAnalysis {
  final int score;
  final String suggestion;

  const ExpressionAnalysis({required this.score, required this.suggestion});
}

class AICoachAnalysis {
  final int score; // 1-10
  final GrammarAnalysis grammar;
  final VocabularyAnalysis vocabulary;
  final ExpressionAnalysis expression;
  final String correctedText;
  final String encouragement;

  const AICoachAnalysis({
    required this.score,
    required this.grammar,
    required this.vocabulary,
    required this.expression,
    required this.correctedText,
    required this.encouragement,
  });
}

// ═══════════════════════════════════════════════════════
// 聊天消息模型
// ═══════════════════════════════════════════════════════

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final SenderRole senderRole;
  final MessageType type;
  final String content;
  final AICoachAnalysis? aiAnalysis;
  final String? correctionNote;
  final int? voiceDuration;
  final DateTime timestamp;
  final bool isEnglish;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.senderRole,
    required this.type,
    required this.content,
    this.aiAnalysis,
    this.correctionNote,
    this.voiceDuration,
    required this.timestamp,
    this.isEnglish = false,
  });
}

// ═══════════════════════════════════════════════════════
// 聊天列表项模型
// ═══════════════════════════════════════════════════════

class ChatItem {
  final String id;
  final ChatItemType type;
  final String name;
  final String avatar;
  final String subtitle;
  final String lastTime;
  final int unread;
  final bool pinned;

  // 单聊特有
  final bool isOnline;
  final String? nationality;

  // 群聊特有
  final int? memberCount;

  // 功能空间特有
  final String? featureIcon;
  final Color? featureColor;
  final String? featureDesc;
  final String? featurePath;

  // 活动空间特有
  final ActivityStatus? activityStatus;
  final String? activityTime;
  final String? activityPath;
  final int? participantCount;

  // 作业特有
  final HomeworkStatus? homeworkStatus;
  final String? homeworkDeadline;
  final String? homeworkPath;

  // 通知特有
  final String? notificationPath;

  // 标签
  final List<String> tags;

  const ChatItem({
    required this.id,
    required this.type,
    required this.name,
    required this.avatar,
    required this.subtitle,
    required this.lastTime,
    required this.unread,
    this.pinned = false,
    this.isOnline = false,
    this.nationality,
    this.memberCount,
    this.featureIcon,
    this.featureColor,
    this.featureDesc,
    this.featurePath,
    this.activityStatus,
    this.activityTime,
    this.activityPath,
    this.participantCount,
    this.homeworkStatus,
    this.homeworkDeadline,
    this.homeworkPath,
    this.notificationPath,
    this.tags = const [],
  });
}

// ═══════════════════════════════════════════════════════
// 筛选标签
// ═══════════════════════════════════════════════════════

class ChatFilter {
  final String key;
  final String label;
  final Color color;
  final ChatItemType? type;

  const ChatFilter({
    required this.key,
    required this.label,
    required this.color,
    this.type,
  });
}

final List<ChatFilter> chatFilters = [
  const ChatFilter(key: 'all', label: '全部', color: Color(0xFF3B3486)),
  const ChatFilter(key: 'homework', label: '作业', color: Color(0xFFF59E0B), type: ChatItemType.homework),
  const ChatFilter(key: 'direct', label: '私聊', color: Color(0xFF10B981), type: ChatItemType.direct),
  const ChatFilter(key: 'group', label: '群聊', color: Color(0xFF3B82F6), type: ChatItemType.group),
  const ChatFilter(key: 'feature', label: '功能', color: Color(0xFF7C3AED), type: ChatItemType.feature),
  const ChatFilter(key: 'activity', label: '活动', color: Color(0xFFF59E0B), type: ChatItemType.activity),
  const ChatFilter(key: 'notification', label: '通知', color: Color(0xFF3B82F6), type: ChatItemType.notification),
];

// ═══════════════════════════════════════════════════════
// 安全过滤
// ═══════════════════════════════════════════════════════

const List<String> _bannedWords = [
  '微信号', 'wx', 'vx', 'QQ', 'qq号', '加我', '私聊', '转账',
  '红包', '赌', '博彩', '色情', '广告', '代购', '代理',
  '刷单', '兼职', '日赚', '投资', '理财', '贷款',
];

class FilterResult {
  final String filtered;
  final List<String> warnings;

  const FilterResult({required this.filtered, required this.warnings});
}

FilterResult filterMessage(String text) {
  final warnings = <String>[];
  var filtered = text;

  final found = _bannedWords.where(
    (w) => text.toLowerCase().contains(w.toLowerCase()),
  ).toList();

  if (found.isNotEmpty) {
    warnings.add('检测到违禁词：${found.join('、')}');
    for (final w in found) {
      filtered = filtered.replaceAll(
        RegExp(w, caseSensitive: false),
        '*' * w.length,
      );
    }
  }

  final qrPattern = RegExp(
    r'https?://qr\.|https?://u\.wechat\.com|https?://weixin\.qq\.com',
    caseSensitive: false,
  );
  if (qrPattern.hasMatch(text)) {
    warnings.add('检测到二维码/外部链接，已屏蔽');
    filtered = filtered.replaceAll(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      '[链接已屏蔽]',
    );
  }

  return FilterResult(filtered: filtered, warnings: warnings);
}

/// 检测是否为英文文本
bool isEnglishText(String text) {
  final englishChars = text.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
  return englishChars / (text.length > 0 ? text.length : 1) > 0.5;
}

// ═══════════════════════════════════════════════════════
// Mock 聊天列表数据
// ═══════════════════════════════════════════════════════

final List<ChatItem> mockChatList = [
  // 置顶 - 杨妈数字人聊天
  const ChatItem(
    id: 'yangma-digital',
    type: ChatItemType.feature,
    name: '杨妈数字人',
    avatar: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=100&h=100&fit=crop',
    subtitle: 'Hi! 我是杨妈，随时可以和我练习英语哦~',
    lastTime: '刚刚',
    unread: 1,
    pinned: true,
    featureIcon: '🧑‍🏫',
    featureColor: Color(0xFFF97316),
    featureDesc: '杨妈AI数字人，练英语、问课程、聊天都可以',
    featurePath: '/chat/yangma-digital',
    tags: ['数字人', 'AI对话', '英语练习'],
  ),
  // 置顶 - 智能客服
  const ChatItem(
    id: 'smart-cs',
    type: ChatItemType.feature,
    name: '途正智能客服',
    avatar: '',
    subtitle: '您好！有任何问题都可以问我~',
    lastTime: '在线',
    unread: 0,
    pinned: true,
    featureIcon: '🤖',
    featureColor: Color(0xFF3B82F6),
    featureDesc: '智能客服 · 知识库问答 · 课程咨询 · 售后服务',
    featurePath: '/chat/smart-cs',
    tags: ['客服', 'AI问答', '知识库'],
  ),
  // 置顶 - 功能空间
  const ChatItem(
    id: 'feature-daily-english',
    type: ChatItemType.feature,
    name: '每日英语角',
    avatar: '',
    subtitle: '今日话题：If you could travel anywhere...',
    lastTime: '09:30',
    unread: 3,
    pinned: true,
    featureIcon: '🌍',
    featureColor: Color(0xFF7C3AED),
    featureDesc: '每天一个话题，用英语自由表达，AI实时评分',
    featurePath: '/feature-daily-english',
    tags: ['口语练习', 'AI评分'],
  ),
  const ChatItem(
    id: 'feature-pronunciation',
    type: ChatItemType.feature,
    name: '发音诊所',
    avatar: '',
    subtitle: '本周挑战：th / ð / θ 发音训练',
    lastTime: '昨天',
    unread: 0,
    pinned: true,
    featureIcon: '🎙️',
    featureColor: Color(0xFFEC4899),
    featureDesc: '跟读练习 + AI发音评测 + 外教纠音',
    featurePath: '/feature-pronunciation',
    tags: ['发音', '跟读'],
  ),
  // 活动空间
  const ChatItem(
    id: 'activity-debate',
    type: ChatItemType.activity,
    name: '英语辩论赛：AI是否会取代老师？',
    avatar: '',
    subtitle: '正方 vs 反方 · 外教主持',
    lastTime: '今天 19:00',
    unread: 12,
    pinned: true,
    activityStatus: ActivityStatus.upcoming,
    activityTime: '今晚 19:00-20:30',
    activityPath: '/activity/debate',
    participantCount: 28,
    featureIcon: '🎤',
    featureColor: Color(0xFFF59E0B),
    tags: ['辩论', '口语'],
  ),
  // 作业
  const ChatItem(
    id: 'homework-writing',
    type: ChatItemType.homework,
    name: '雅思写作 Task2 练习',
    avatar: '',
    subtitle: 'Topic: Technology in Education',
    lastTime: '10:00',
    unread: 1,
    pinned: false,
    homeworkStatus: HomeworkStatus.pending,
    homeworkDeadline: '明天 23:59',
    homeworkPath: '/homework/writing',
    tags: ['写作', '雅思'],
  ),
  const ChatItem(
    id: 'homework-reading',
    type: ChatItemType.homework,
    name: '阅读理解 - Cambridge 18',
    avatar: '',
    subtitle: '已提交，等待老师批改',
    lastTime: '昨天',
    unread: 0,
    pinned: false,
    homeworkStatus: HomeworkStatus.submitted,
    homeworkPath: '/homework/reading',
    tags: ['阅读'],
  ),
  const ChatItem(
    id: 'homework-listening',
    type: ChatItemType.homework,
    name: '听力精听 - Section 3',
    avatar: '',
    subtitle: '得分: 8/10 · 外教点评已出',
    lastTime: '前天',
    unread: 1,
    pinned: false,
    homeworkStatus: HomeworkStatus.graded,
    homeworkPath: '/homework/listening',
    tags: ['听力'],
  ),
  // 私聊
  const ChatItem(
    id: 'direct-teacher-sarah',
    type: ChatItemType.direct,
    name: 'Sarah老师',
    avatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
    subtitle: 'Your essay is getting better! Keep it up 👍',
    lastTime: '14:30',
    unread: 2,
    isOnline: true,
    nationality: '🇲🇲',
    tags: ['外教'],
  ),
  const ChatItem(
    id: 'direct-classmate-emma',
    type: ChatItemType.direct,
    name: 'Emma',
    avatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&crop=face',
    subtitle: '明天一起去图书馆练口语吗？',
    lastTime: '12:15',
    unread: 0,
    isOnline: false,
    nationality: '🇨🇳',
    tags: ['同学'],
  ),
  // 群聊
  const ChatItem(
    id: 'group-ielts-7',
    type: ChatItemType.group,
    name: '雅思7分冲刺班',
    avatar: '',
    subtitle: '李明: 大家今天的写作练习做了吗？',
    lastTime: '15:30',
    unread: 5,
    memberCount: 32,
    tags: ['雅思', '备考'],
  ),
  const ChatItem(
    id: 'group-oral-practice',
    type: ChatItemType.group,
    name: '口语练习小组',
    avatar: '',
    subtitle: 'Emma: Let\'s practice together!',
    lastTime: '11:00',
    unread: 0,
    memberCount: 8,
    tags: ['口语'],
  ),
  // 通知
  const ChatItem(
    id: 'notification-system',
    type: ChatItemType.notification,
    name: '系统通知',
    avatar: '',
    subtitle: '您的课程已更新，请查看最新安排',
    lastTime: '08:00',
    unread: 1,
    notificationPath: '/notifications',
  ),
  const ChatItem(
    id: 'notification-activity',
    type: ChatItemType.notification,
    name: '活动通知',
    avatar: '',
    subtitle: '英语辩论赛报名截止提醒',
    lastTime: '昨天',
    unread: 0,
    notificationPath: '/notifications',
  ),
];

// ═══════════════════════════════════════════════════════
// Mock 聊天消息数据
// ═══════════════════════════════════════════════════════

final Map<String, List<ChatMessage>> mockChatMessages = {
  'yangma-digital': [
    ChatMessage(
      id: 'ym-1',
      senderId: 'yangma',
      senderName: '杨妈',
      senderAvatar: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=100&h=100&fit=crop',
      senderRole: SenderRole.ai,
      type: MessageType.text,
      content: 'Hello! 我是杨妈 😊\n\n欢迎来到途正英语！我是你的AI英语教练，可以帮你：\n\n🗣️ 练习英语口语\n📝 检查英语写作\n📚 解答课程问题\n💡 分享学习技巧\n\n直接用英语和我聊天吧！我会自动帮你评分和纠错哦~',
      timestamp: DateTime(2026, 3, 9, 8, 0),
    ),
    ChatMessage(
      id: 'ym-2',
      senderId: 's1',
      senderName: '我',
      senderAvatar: '',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: 'Hello Yang Ma! I want to practice my speaking skills for the IELTS exam.',
      timestamp: DateTime(2026, 3, 9, 8, 5),
      isEnglish: true,
    ),
    ChatMessage(
      id: 'ym-2-ai',
      senderId: 'ai',
      senderName: 'AI 教练',
      senderAvatar: '',
      senderRole: SenderRole.ai,
      type: MessageType.aiCoach,
      content: '',
      timestamp: DateTime(2026, 3, 9, 8, 5, 5),
      aiAnalysis: const AICoachAnalysis(
        score: 7,
        grammar: GrammarAnalysis(score: 7, issues: ['语法正确，"want to" 使用恰当']),
        vocabulary: VocabularyAnalysis(score: 6, level: 'B2 中高级'),
        expression: ExpressionAnalysis(
          score: 7,
          suggestion: '可以说 "I\'d like to improve my speaking skills" 更地道',
        ),
        correctedText: 'Hello Yang Ma! I\'d like to practice my speaking skills for the IELTS exam.',
        encouragement: '开口说英语就是最大的进步！继续加油 💪',
      ),
    ),
    ChatMessage(
      id: 'ym-3',
      senderId: 'yangma',
      senderName: '杨妈',
      senderAvatar: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=100&h=100&fit=crop',
      senderRole: SenderRole.ai,
      type: MessageType.text,
      content: 'Great! I\'m so glad you want to practice! 🌟\n\nLet\'s start with a common IELTS topic:\n\n"Do you think technology has more positive or negative effects on education?"\n\nTry to answer in 2-3 sentences. I\'ll give you feedback!',
      timestamp: DateTime(2026, 3, 9, 8, 6),
    ),
  ],
  'smart-cs': [
    ChatMessage(
      id: 'cs-1',
      senderId: 'smart-cs',
      senderName: '途正智能客服',
      senderAvatar: '',
      senderRole: SenderRole.ai,
      type: MessageType.text,
      content: '😊 您好！欢迎来到途正英语！\n\n我是智能客服小途，可以帮您解答：\n• 课程咨询与推荐\n• 价格与套餐说明\n• 老师介绍\n• 退款与售后\n• 学习方法建议\n\n请输入您的问题，或输入关键词如"课程""价格""老师""雅思"等。',
      timestamp: DateTime(2026, 3, 9, 9, 0),
    ),
  ],
  'feature-daily-english': [
    ChatMessage(
      id: 'fe-1',
      senderId: 'system',
      senderName: '系统',
      senderAvatar: '',
      senderRole: SenderRole.system,
      type: MessageType.system,
      content: '🌍 今日话题：If you could travel anywhere in the world, where would you go and why? 用英语回答，AI自动评分！',
      timestamp: DateTime(2026, 3, 9, 9, 0),
    ),
    ChatMessage(
      id: 'fe-2',
      senderId: 's1',
      senderName: '我',
      senderAvatar: '',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: 'If I could travel anywhere, I would choose to visit Japan. The reason is that I am fascinated by Japanese culture, especially their traditional architecture and cuisine.',
      timestamp: DateTime(2026, 3, 9, 9, 15),
      isEnglish: true,
    ),
    ChatMessage(
      id: 'fe-2-ai',
      senderId: 'ai',
      senderName: 'AI 教练',
      senderAvatar: '',
      senderRole: SenderRole.ai,
      type: MessageType.aiCoach,
      content: '',
      timestamp: DateTime(2026, 3, 9, 9, 15, 5),
      aiAnalysis: const AICoachAnalysis(
        score: 8,
        grammar: GrammarAnalysis(score: 9, issues: ['语法完美，虚拟语气使用正确']),
        vocabulary: VocabularyAnalysis(score: 8, level: 'C1 高级'),
        expression: ExpressionAnalysis(
          score: 8,
          suggestion: '可以加入更具体的细节，如 "I\'m particularly drawn to the serene beauty of Kyoto\'s temples"',
        ),
        correctedText: 'If I could travel anywhere, I would choose to visit Japan. The reason is that I am fascinated by Japanese culture, especially their traditional architecture and exquisite cuisine.',
        encouragement: '非常棒的回答！虚拟语气运用自如，表达地道 🌟',
      ),
    ),
  ],
  'group-ielts-7': [
    ChatMessage(
      id: 'grp-1',
      senderId: 'system',
      senderName: '系统',
      senderAvatar: '',
      senderRole: SenderRole.system,
      type: MessageType.system,
      content: '欢迎加入「雅思7分冲刺班」！请遵守群规，友好交流。',
      timestamp: DateTime(2026, 3, 9, 10, 0),
    ),
    ChatMessage(
      id: 'grp-2',
      senderId: 's2',
      senderName: 'Tom',
      senderAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&crop=face',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: 'In my opinion, technology has both positive and negative effects on education. On the one hand, it provides students with access to vast resources.',
      timestamp: DateTime(2026, 3, 9, 15, 0),
      isEnglish: true,
    ),
    ChatMessage(
      id: 'grp-2-ai',
      senderId: 'ai',
      senderName: 'AI 教练',
      senderAvatar: '',
      senderRole: SenderRole.ai,
      type: MessageType.aiCoach,
      content: '',
      timestamp: DateTime(2026, 3, 9, 15, 0, 5),
      aiAnalysis: const AICoachAnalysis(
        score: 7,
        grammar: GrammarAnalysis(score: 7, issues: ['语法正确，"On the one hand" 连接词使用得当']),
        vocabulary: VocabularyAnalysis(score: 6, level: 'B2 中高级'),
        expression: ExpressionAnalysis(
          score: 6,
          suggestion: '"vast resources" 很好！可以进一步丰富为 "a wealth of educational resources"',
        ),
        correctedText: 'In my opinion, technology has both positive and negative effects on education. On the one hand, it provides students with access to a wealth of educational resources.',
        encouragement: '观点表达清晰，注意第三人称单数的一致性 📝',
      ),
    ),
    ChatMessage(
      id: 'grp-3',
      senderId: 's3',
      senderName: '李明',
      senderAvatar: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop&crop=face',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: '大家今天的写作练习做了吗？',
      timestamp: DateTime(2026, 3, 9, 15, 30),
    ),
  ],
  'direct-teacher-sarah': [
    ChatMessage(
      id: 'ts-1',
      senderId: 'teacher-sarah',
      senderName: 'Sarah老师',
      senderAvatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
      senderRole: SenderRole.foreignTeacher,
      type: MessageType.text,
      content: 'Hi Lily! I\'ve reviewed your latest essay. Your essay is getting better! Keep it up 👍\n\nI noticed you\'ve improved a lot in using complex sentences. Just pay attention to article usage.',
      timestamp: DateTime(2026, 3, 9, 14, 30),
    ),
    ChatMessage(
      id: 'ts-2',
      senderId: 's1',
      senderName: '我',
      senderAvatar: '',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: 'Thank you Sarah! I will pay more attention to articles. Could you recommend some exercises for that?',
      timestamp: DateTime(2026, 3, 9, 14, 35),
      isEnglish: true,
    ),
  ],
};

// ═══════════════════════════════════════════════════════
// 工具函数
// ═══════════════════════════════════════════════════════

/// 获取聊天项的图标和颜色
({String icon, Color color}) getChatItemIcon(ChatItem chat) {
  if (chat.type == ChatItemType.homework) {
    switch (chat.homeworkStatus) {
      case HomeworkStatus.pending:
        return (icon: '✏️', color: const Color(0xFFF59E0B));
      case HomeworkStatus.submitted:
        return (icon: '✅', color: const Color(0xFF10B981));
      case HomeworkStatus.graded:
        return (icon: '📊', color: const Color(0xFF7C3AED));
      default:
        return (icon: '✏️', color: const Color(0xFFF59E0B));
    }
  }
  if (chat.type == ChatItemType.notification) {
    return (icon: '🔔', color: const Color(0xFF3B82F6));
  }
  switch (chat.type) {
    case ChatItemType.feature:
      return (icon: chat.featureIcon ?? '🔧', color: chat.featureColor ?? const Color(0xFF7C3AED));
    case ChatItemType.activity:
      return (icon: chat.featureIcon ?? '🎯', color: chat.featureColor ?? const Color(0xFFF59E0B));
    case ChatItemType.group:
      return (icon: '👥', color: const Color(0xFF3B82F6));
    default:
      return (icon: '', color: Colors.grey);
  }
}

/// 获取活动状态标签
({String text, Color color, Color bg}) getActivityStatusLabel(ActivityStatus? status) {
  switch (status) {
    case ActivityStatus.upcoming:
      return (text: '即将开始', color: const Color(0xFFF59E0B), bg: const Color(0xFFFEF3C7));
    case ActivityStatus.ongoing:
      return (text: '进行中', color: const Color(0xFF10B981), bg: const Color(0xFFD1FAE5));
    case ActivityStatus.ended:
      return (text: '已结束', color: const Color(0xFF6B7280), bg: const Color(0xFFF3F4F6));
    default:
      return (text: '', color: Colors.transparent, bg: Colors.transparent);
  }
}

/// 获取类型指示条颜色
Color getTypeColor(ChatItemType type) {
  switch (type) {
    case ChatItemType.direct:
      return const Color(0xFF10B981);
    case ChatItemType.group:
      return const Color(0xFF3B82F6);
    case ChatItemType.feature:
      return const Color(0xFF7C3AED);
    case ChatItemType.activity:
      return const Color(0xFFF59E0B);
    case ChatItemType.homework:
      return const Color(0xFFF59E0B);
    case ChatItemType.notification:
      return const Color(0xFF3B82F6);
  }
}

/// 生成 Mock AI 评分
AICoachAnalysis generateMockAnalysis(String text) {
  final wordCount = text.split(RegExp(r'\s+')).length;
  final hasComplex = RegExp(r'although|however|nevertheless|furthermore|moreover', caseSensitive: false).hasMatch(text);
  final baseScore = (wordCount ~/ 3 + (hasComplex ? 2 : 0)).clamp(4, 9);
  return AICoachAnalysis(
    score: baseScore,
    grammar: GrammarAnalysis(
      score: (baseScore - 1).clamp(4, 10),
      issues: wordCount < 5
          ? ['句子较短，尝试使用更完整的句式表达']
          : ['语法基本正确，注意时态一致性'],
    ),
    vocabulary: VocabularyAnalysis(
      score: baseScore,
      level: baseScore >= 7 ? 'C1 高级' : baseScore >= 5 ? 'B2 中高级' : 'B1 中级',
    ),
    expression: ExpressionAnalysis(
      score: (baseScore + 1).clamp(1, 10),
      suggestion: '尝试使用更多高级词汇和复杂句式来提升表达质量',
    ),
    correctedText: text,
    encouragement: baseScore >= 7 ? '表达非常棒！继续保持 🌟' : '不错的尝试，继续加油 💪',
  );
}

/// 杨妈自动回复
const List<String> yangmaReplies = [
  'That\'s a great question! 😊 Let me explain...\n\n这个问题很好！在英语学习中，最重要的是坚持每天练习。我建议你每天花15分钟做口语练习，效果会很明显的！',
  'Excellent! Your English is improving! 🌟\n\n你的进步很明显！注意一下时态的使用，过去式和现在完成时要区分清楚。继续加油！',
  'Good try! Let me give you some tips... 💡\n\n你说得不错！我教你一个小技巧：用"I\'d rather...than..."这个句型可以让你的表达更地道。试试看！',
  'I\'m so proud of your progress! 🎉\n\n你的词汇量在增长！建议你试试我们的单词速记功能，用快速记忆法每天背5个单词，一个月就能记住150个新词！',
  'That\'s interesting! Tell me more... 🤔\n\n很有趣的观点！在雅思口语考试中，考官很喜欢听到有个人见解的回答。你可以多用"In my opinion"、"From my perspective"这样的表达。',
];

/// 智能客服关键词回复
const Map<String, String> csReplies = {
  '课程': '📚 途正英语提供多种课程选择：\n\n1️⃣ 雅思培训课程 - 含听说读写四科专项训练\n2️⃣ 外教一对一 - 25分钟外教口语课\n3️⃣ 磨课课程 - AI预磨课+教练精批+直播磨课\n4️⃣ 视频录播课 - 随时随地学习\n\n您可以在"课程商城"中查看详情！',
  '价格': '💰 课程价格参考：\n\n• 外教一对一试课 - ¥19.9/25分钟\n• 10节套餐 - ¥47/节/25分钟\n• 20节套餐 - ¥43/节/25分钟\n• 40节套餐 - ¥39/节/25分钟\n\n套餐越大越优惠！',
  '退款': '💳 退款政策：\n\n• 未开始的课程可全额退款\n• 已上过的课时按实际价格扣除\n• 退款申请请联系人工客服',
  '老师': '👩‍🏫 我们的外教团队：\n\n全部持有TESOL/TEFL证书，平均教学经验5年以上。\n\n您可以通过"约课调研"功能，系统会根据您的需求智能推荐最合适的老师！',
  '雅思': '🎓 雅思培训服务：\n\n• 分级测试 - 一次检测全站通用\n• AI写作批改 - 30秒内出评分\n• AI发音评测 - 实时纠正发音\n• 外教精批 - 24小时内返回\n\n建议先做分级测试，了解自己的水平后再选择课程！',
};

const String csDefaultReply = '😊 感谢您的咨询！\n\n我是途正英语智能客服，可以帮您解答：\n• 课程咨询与推荐\n• 价格与套餐说明\n• 老师介绍\n• 退款与售后\n• 学习方法建议\n\n请输入您的问题，或输入关键词如"课程""价格""老师""雅思"等。';
