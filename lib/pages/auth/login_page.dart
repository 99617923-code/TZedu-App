/// 途正英语 - 登录页面
/// 火鹰科技出品
///
/// 支持两种登录方式：
/// 1. 手机号 + 密码
/// 2. 手机号 + 短信验证码
///
/// 对标原型设计，紫色渐变主题
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginPage({super.key, this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  // Tab 控制
  late TabController _tabController;
  int _currentTab = 0; // 0=密码登录, 1=验证码登录

  // 表单控制器
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _smsCodeController = TextEditingController();

  // 状态
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // 验证码倒计时
  int _smsCountdown = 0;
  Timer? _smsTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _currentTab = _tabController.index;
        _errorMessage = null;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _smsCodeController.dispose();
    _smsTimer?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 登录逻辑
  // ═══════════════════════════════════════════════════════

  Future<void> _handleLogin() async {
    final phone = _phoneController.text.trim();

    // 基础校验
    if (phone.isEmpty || phone.length != 11) {
      setState(() => _errorMessage = '请输入正确的手机号');
      return;
    }

    if (_currentTab == 0) {
      // 密码登录
      final password = _passwordController.text;
      if (password.isEmpty) {
        setState(() => _errorMessage = '请输入密码');
        return;
      }
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await AuthService.instance.loginWithPassword(phone, password);
      _handleLoginResult(result);
    } else {
      // 验证码登录
      final code = _smsCodeController.text.trim();
      if (code.isEmpty || code.length != 6) {
        setState(() => _errorMessage = '请输入6位验证码');
        return;
      }
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await AuthService.instance.loginWithSmsCode(phone, code);
      _handleLoginResult(result);
    }
  }

  void _handleLoginResult(LoginResult result) {
    setState(() => _isLoading = false);

    if (result.success) {
      // 登录成功
      widget.onLoginSuccess?.call();
    } else {
      setState(() => _errorMessage = result.message ?? '登录失败');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 发送短信验证码
  // ═══════════════════════════════════════════════════════

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      setState(() => _errorMessage = '请输入正确的手机号');
      return;
    }

    final result = await AuthService.instance.sendSmsCode(phone);
    if (result.success) {
      // 开始倒计时
      setState(() => _smsCountdown = 60);
      _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _smsCountdown--;
          if (_smsCountdown <= 0) {
            timer.cancel();
          }
        });
      });
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  // ═══════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildLoginCard(),
                    const SizedBox(height: 24),
                    _buildFooter(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Logo 图标
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              '途正',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '途正英语',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: TZColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '智慧教学管理系统',
          style: TextStyle(
            fontSize: 14,
            color: TZColors.textGray.withOpacity(0.8),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tab 切换
            _buildTabBar(),
            const SizedBox(height: 24),
            // 手机号输入
            _buildPhoneField(),
            const SizedBox(height: 16),
            // 密码 / 验证码输入
            if (_currentTab == 0) _buildPasswordField() else _buildSmsCodeField(),
            // 错误提示
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorMessage(),
            ],
            const SizedBox(height: 24),
            // 登录按钮
            _buildLoginButton(),
            const SizedBox(height: 16),
            // 忘记密码 / 注册
            _buildBottomLinks(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: TZColors.primaryPurple,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: TZColors.textGray,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: '密码登录'),
          Tab(text: '验证码登录'),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      style: const TextStyle(fontSize: 16, color: TZColors.textDark),
      decoration: InputDecoration(
        hintText: '请输入手机号',
        hintStyle: TextStyle(color: TZColors.textGray.withOpacity(0.5)),
        prefixIcon: const Icon(Icons.phone_android, color: TZColors.primaryPurple, size: 20),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TZColors.primaryPurple, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(fontSize: 16, color: TZColors.textDark),
      decoration: InputDecoration(
        hintText: '请输入密码',
        hintStyle: TextStyle(color: TZColors.textGray.withOpacity(0.5)),
        prefixIcon: const Icon(Icons.lock_outline, color: TZColors.primaryPurple, size: 20),
        suffixIcon: GestureDetector(
          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
          child: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: TZColors.textGray,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TZColors.primaryPurple, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onSubmitted: (_) => _handleLogin(),
    );
  }

  Widget _buildSmsCodeField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _smsCodeController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(fontSize: 16, color: TZColors.textDark),
            decoration: InputDecoration(
              hintText: '请输入验证码',
              hintStyle: TextStyle(color: TZColors.textGray.withOpacity(0.5)),
              prefixIcon: const Icon(Icons.sms_outlined, color: TZColors.primaryPurple, size: 20),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: TZColors.primaryPurple, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => _handleLogin(),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _smsCountdown > 0 ? null : _sendSmsCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: _smsCountdown > 0 ? const Color(0xFFE5E7EB) : TZColors.primaryPurple,
              foregroundColor: _smsCountdown > 0 ? TZColors.textGray : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              _smsCountdown > 0 ? '${_smsCountdown}s' : '获取验证码',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: TZColors.errorRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: TZColors.errorRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: TZColors.primaryPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: TZColors.primaryPurple.withOpacity(0.6),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                '登 录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 4),
              ),
      ),
    );
  }

  Widget _buildBottomLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            // TODO: 跳转注册页
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('注册功能即将开放'), duration: Duration(seconds: 2)),
            );
          },
          child: const Text(
            '新用户注册',
            style: TextStyle(color: TZColors.primaryPurple, fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () {
            // TODO: 跳转找回密码页
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('找回密码功能即将开放'), duration: Duration(seconds: 2)),
            );
          },
          child: Text(
            '忘记密码？',
            style: TextStyle(color: TZColors.textGray.withOpacity(0.7), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          '登录即表示同意',
          style: TextStyle(color: TZColors.textGray.withOpacity(0.6), fontSize: 12),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {},
              child: const Text(
                '《用户协议》',
                style: TextStyle(color: TZColors.primaryPurple, fontSize: 12),
              ),
            ),
            Text(' 和 ', style: TextStyle(color: TZColors.textGray.withOpacity(0.6), fontSize: 12)),
            GestureDetector(
              onTap: () {},
              child: const Text(
                '《隐私政策》',
                style: TextStyle(color: TZColors.primaryPurple, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '途正教育 · 火鹰科技',
          style: TextStyle(color: TZColors.textGray.withOpacity(0.4), fontSize: 11),
        ),
      ],
    );
  }
}
