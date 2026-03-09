import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';

import '../../common.dart';
import 'privacy_policy.dart' as policy_pages;
import '../terms_of_service.dart' as policy_pages;

/// 应用注册页面
class AppRegisterPage extends StatefulWidget {
  const AppRegisterPage({Key? key}) : super(key: key);

  @override
  State<AppRegisterPage> createState() => _AppRegisterPageState();
}

class _AppRegisterPageState extends State<AppRegisterPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _activationCodeController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _smsCodeFocus = FocusNode();
  final _activationCodeFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isSendingSms = false;
  String? _errorMsg;
  String? _passwordFormatError;

  int _countdown = 0;
  Timer? _countdownTimer;

  final _authService = AppAuthService();

  bool _agreedToTerms = false;
  final String _agreedTermsVersionKey = 'agreed_terms_version';
  final String _agreedPrivacyVersionKey = 'agreed_privacy_version';
  final String _currentTermsVersion = policy_pages.termsOfServiceVersion;
  final String _currentPrivacyVersion = policy_pages.privacyPolicyVersion;

  @override
  void initState() {
    super.initState();
    // Check local storage for agreed terms version
    _agreedToTerms = bind.mainGetLocalOption(key: _agreedTermsVersionKey) == _currentTermsVersion &&
                     bind.mainGetLocalOption(key: _agreedPrivacyVersionKey) == _currentPrivacyVersion;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _activationCodeController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _phoneFocus.dispose();
    _smsCodeFocus.dispose();
    _activationCodeFocus.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
      } else {
        if (mounted) setState(() => _countdown--);
      }
    });
  }

  bool _isPasswordValid(String value) {
    if (value.length < 6 || value.length > 20) return false;
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'\d'));
    return hasLetter && hasDigit;
  }

  String? _validatePasswordFormat(String value) {
    if (value.isEmpty) return null;
    if (value.length < 6 || value.length > 20) {
      return '密码需为6-20位字符';
    }
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) {
      return '密码需包含字母和数字';
    }
    return null;
  }

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = '请输入手机号');
      return;
    }
    setState(() {
      _isSendingSms = true;
      _errorMsg = null;
    });
    final error = await _authService.sendSmsCode(phone: phone);
    if (!mounted) return;
    setState(() => _isSendingSms = false);
    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }
    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('验证码已发送')),
    );
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final phone = _phoneController.text.trim();
    final smsCode = _smsCodeController.text.trim();
    final activationCode = _activationCodeController.text.trim();

    if (username.isEmpty) {
      setState(() => _errorMsg = '请输入用户名');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMsg = '请输入密码');
      return;
    }
    if (!_isPasswordValid(password)) {
      setState(() => _errorMsg = '密码需为6-20位字符，且包含字母和数字');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMsg = '两次密码输入不一致');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _errorMsg = '请输入手机号');
      return;
    }
    if (smsCode.isEmpty) {
      setState(() => _errorMsg = '请输入验证码');
      return;
    }
    if (activationCode.isEmpty) {
      setState(() => _errorMsg = '请输入激活码');
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _errorMsg = '请先阅读并同意《用户协议》与《隐私政策》');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final error = await _authService.register(
      username: username,
      password: password,
      phone: phone,
      smsCode: smsCode,
      activationCode: activationCode,
      agreedTermsVersion: _currentTermsVersion,
      agreedPrivacyVersion: _currentPrivacyVersion,
      agreedTime: DateTime.now().toIso8601String(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        setState(() => _errorMsg = error);
      } else {
        bind.mainSetLocalOption(key: _agreedTermsVersionKey, value: _currentTermsVersion);
        bind.mainSetLocalOption(key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
        // 注册成功，返回登录页
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('注册成功，请登录'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('注册账号'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              children: [
                // Username
                _buildTextField(
                  controller: _usernameController,
                  focusNode: _usernameFocus,
                  label: '用户名',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 14),
                // Password
                _buildTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  label: '密码',
                  icon: Icons.lock_outline,
                  obscure: _obscurePassword,
                  onChanged: (value) {
                    final error = _validatePasswordFormat(value);
                    if (error != _passwordFormatError) {
                      setState(() => _passwordFormatError = error);
                    }
                  },
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                if (_passwordFormatError != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _passwordFormatError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Confirm Password
                _buildTextField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocus,
                  label: '确认密码',
                  icon: Icons.lock_outline,
                  obscure: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                  ),
                ),
                const SizedBox(height: 14),
                // Phone
                _buildTextField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  label: '手机号',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _smsCodeController,
                        focusNode: _smsCodeFocus,
                        label: '验证码',
                        icon: Icons.sms_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_countdown > 0 || _isSendingSms)
                            ? null
                            : _sendSmsCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyTheme.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 0,
                        ),
                        child: Text(
                          _countdown > 0 ? '${_countdown}s' : '获取验证码',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Activation Code
                _buildTextField(
                  controller: _activationCodeController,
                  focusNode: _activationCodeFocus,
                  label: '激活码',
                  icon: Icons.vpn_key_outlined,
                ),
                // Terms of Service Checkbox
                _buildTermsCheckbox(isDark),

                const SizedBox(height: 16),

                // Error message
                if (_errorMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMsg!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Register Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '注 册',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '已有账号？',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        '去登录',
                        style: TextStyle(
                          color: MyTheme.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTermsCheckbox(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreedToTerms,
            activeColor: MyTheme.accent,
            onChanged: (val) {
              setState(() => _agreedToTerms = val ?? false);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              children: [
                Text(
                  '我已阅读并同意',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    // Navigate to Terms of Service
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const policy_pages.TermsOfServicePage(),
                      ),
                    );
                  },
                  child: Text(
                    '《用户协议》',
                    style: TextStyle(
                      fontSize: 12,
                      color: MyTheme.accent,
                    ),
                  ),
                ),
                Text(
                  '与',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    // Navigate to Privacy Policy
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const policy_pages.PrivacyPolicyPage(),
                      ),
                    );
                  },
                  child: Text(
                    '《隐私政策》',
                    style: TextStyle(
                      fontSize: 12,
                      color: MyTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            labelText: hasFocus ? label : null,
            hintText: hasFocus ? null : label,
            floatingLabelBehavior: hasFocus
                ? FloatingLabelBehavior.always
                : FloatingLabelBehavior.never,
            labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            floatingLabelStyle: TextStyle(
              color: MyTheme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: MyTheme.accent, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            isDense: false,
          ),
        );
      },
    );
  }
}
