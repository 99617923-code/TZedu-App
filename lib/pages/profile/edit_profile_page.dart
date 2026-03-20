/// 途正英语 - 编辑个人资料页面
/// 火鹰科技出品
///
/// 支持修改昵称和头像 URL
/// 修改后自动同步到网易云信 IM 系统
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nicknameController = TextEditingController();
  final _avatarController = TextEditingController();
  bool _isLoading = false;
  String? _successMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    if (user != null) {
      _nicknameController.text = user.nickname;
      _avatarController.text = user.avatar;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    final avatar = _avatarController.text.trim();

    if (nickname.isEmpty) {
      setState(() => _errorMessage = '昵称不能为空');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final success = await AuthService.instance.updateProfile(
      nickname: nickname,
      avatar: avatar.isNotEmpty ? avatar : null,
    );

    setState(() {
      _isLoading = false;
      if (success) {
        _successMessage = '资料更新成功';
      } else {
        _errorMessage = '更新失败，请稍后重试';
      }
    });

    if (success && mounted) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [TZColors.bgStart, TZColors.bgPurple, TZColors.bgMid, TZColors.bgEnd],
            stops: [0.0, 0.15, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    ),
                    const Expanded(
                      child: Text(
                        '编辑资料',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TZColors.textDark),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: TZColors.primaryPurple))
                          : const Text('保存', style: TextStyle(color: TZColors.primaryPurple, fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ],
                ),
              ),
              // 内容
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      children: [
                        // 头像预览
                        _buildAvatarPreview(user),
                        const SizedBox(height: 32),
                        // 昵称
                        _buildField(
                          label: '昵称',
                          controller: _nicknameController,
                          hint: '请输入昵称',
                          icon: Icons.person_outline,
                          maxLength: 20,
                        ),
                        const SizedBox(height: 20),
                        // 头像 URL
                        _buildField(
                          label: '头像链接',
                          controller: _avatarController,
                          hint: '请输入头像图片 URL（可选）',
                          icon: Icons.link,
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '修改后将自动同步到 IM 消息系统',
                            style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.6)),
                          ),
                        ),

                        // 消息提示
                        if (_successMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TZColors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: TZColors.green, size: 18),
                                const SizedBox(width: 8),
                                Text(_successMessage!, style: const TextStyle(color: TZColors.green, fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TZColors.errorRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: TZColors.errorRed, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_errorMessage!, style: const TextStyle(color: TZColors.errorRed, fontSize: 14)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPreview(UserProfile? user) {
    final initial = (user != null && user.nickname.isNotEmpty) ? user.nickname[0] : '?';

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          user?.nickname ?? '',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TZColors.textDark),
        ),
        if (user?.phone != null)
          Text(
            user!.phone!,
            style: TextStyle(fontSize: 13, color: TZColors.textGray.withOpacity(0.6)),
          ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TZColors.textDark)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, color: TZColors.textDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: TZColors.textGray.withOpacity(0.5)),
            prefixIcon: Icon(icon, color: TZColors.primaryPurple, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: TZColors.primaryPurple, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            counterText: '',
          ),
        ),
      ],
    );
  }
}
