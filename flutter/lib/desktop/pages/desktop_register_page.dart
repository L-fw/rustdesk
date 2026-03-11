import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;

/// 桌面端注册页面
class AppRegisterPage extends StatefulWidget {
  const AppRegisterPage({Key? key}) : super(key: key);

  @override
  State<AppRegisterPage> createState() => _AppRegisterPageState();
}

class _AppRegisterPageState extends State<AppRegisterPage>
    with SingleTickerProviderStateMixin {
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
  final String _currentTermsVersion = terms_pages.termsOfServiceVersion;
  final String _currentPrivacyVersion = privacy_pages.privacyPolicyVersion;
  final Map<String, AnimationController> _shakeControllers = {};
  final Map<String, bool> _invalidFields = {};

  @override
  void initState() {
    super.initState();
    _shakeControllers['username'] = _createShakeController();
    _shakeControllers['password'] = _createShakeController();
    _shakeControllers['confirmPassword'] = _createShakeController();
    _shakeControllers['phone'] = _createShakeController();
    _shakeControllers['sms'] = _createShakeController();
    _shakeControllers['activation'] = _createShakeController();
    _shakeControllers['terms'] = _createShakeController();
  }

  @override
  void dispose() {
    for (final controller in _shakeControllers.values) {
      controller.dispose();
    }
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

  AnimationController _createShakeController() {
    return AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  void _setFieldError(String key, FocusNode node, String message) {
    setState(() {
      _errorMsg = message;
      _invalidFields[key] = true;
    });
    _shakeControllers[key]?.forward(from: 0);
    if (!node.hasFocus) node.requestFocus();
  }

  void _clearFieldError(String key) {
    if (_invalidFields[key] == true) {
      setState(() => _invalidFields[key] = false);
    }
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

  bool _isUsernameValid(String value) {
    return RegExp(r'^[A-Za-z0-9\u4e00-\u9fff]+$').hasMatch(value);
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
      _setFieldError('phone', _phoneFocus, '请输入手机号');
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
      _setFieldError('username', _usernameFocus, '请输入用户名');
      return;
    }
    if (!_isUsernameValid(username)) {
      _setFieldError('username', _usernameFocus, '用户名只能包含中文、英文和数字');
      return;
    }
    if (password.isEmpty) {
      _setFieldError('password', _passwordFocus, '请输入密码');
      return;
    }
    if (!_isPasswordValid(password)) {
      _setFieldError('password', _passwordFocus, '密码需为6-20位字符，且包含字母和数字');
      return;
    }
    if (password != confirmPassword) {
      _setFieldError('confirmPassword', _confirmPasswordFocus, '两次密码输入不一致');
      return;
    }
    if (phone.isEmpty) {
      _setFieldError('phone', _phoneFocus, '请输入手机号');
      return;
    }
    if (smsCode.isEmpty) {
      _setFieldError('sms', _smsCodeFocus, '请输入验证码');
      return;
    }
    if (activationCode.isEmpty) {
      _setFieldError('activation', _activationCodeFocus, '请输入激活码');
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _errorMsg = '请先阅读并同意《用户协议》与《隐私政策》');
      _shakeControllers['terms']?.forward(from: 0);
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
        bind.mainSetLocalOption(
            key: _agreedTermsVersionKey, value: _currentTermsVersion);
        bind.mainSetLocalOption(
            key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
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

    // ── 桌面端：居中卡片布局，不使用 AppBar / SafeArea ──
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5),
      body: Center(
        child: ConstrainedBox(
          // 限制最大宽度，左右留白，让表单在宽屏上不过度拉伸
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: isDark ? 4 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 标题行：图标 + 文字 + 关闭按钮 ──
                  Row(
                    children: [
                      Icon(Icons.person_add_alt_1_outlined,
                          color: MyTheme.accent, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        '注册账号',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      // 关闭按钮（桌面端通常以 X 替代返回箭头）
                      IconButton(
                        icon: Icon(Icons.close,
                            color:
                                isDark ? Colors.white54 : Colors.black45),
                        splashRadius: 18,
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── 用户名 ──
                  _buildTextField(
                    fieldKey: 'username',
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    label: '用户名',
                    icon: Icons.person_outline,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9\u4e00-\u9fff]')),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── 密码 ──
                  _buildTextField(
                    fieldKey: 'password',
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
                      if (error == null && _invalidFields['password'] == true) {
                        _clearFieldError('password');
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
                      splashRadius: 16,
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  if (_passwordFormatError != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _passwordFormatError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // ── 确认密码 ──
                  _buildTextField(
                    fieldKey: 'confirmPassword',
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocus,
                    label: '确认密码',
                    icon: Icons.lock_outline,
                    obscure: _obscureConfirm,
                    onChanged: (value) {
                      if (value == _passwordController.text &&
                          _invalidFields['confirmPassword'] == true) {
                        _clearFieldError('confirmPassword');
                      }
                    },
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.grey,
                      ),
                      splashRadius: 16,
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── 手机号 ──
                  _buildTextField(
                    fieldKey: 'phone',
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    label: '手机号',
                    icon: Icons.phone_android,
                    // 桌面端不设置 keyboardType，避免弹出虚拟键盘提示
                  ),
                  const SizedBox(height: 14),

                  // ── 验证码 + 获取按钮 ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildTextField(
                          fieldKey: 'sms',
                          controller: _smsCodeController,
                          focusNode: _smsCodeFocus,
                          label: '验证码',
                          icon: Icons.sms_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 50,
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
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            elevation: 0,
                          ),
                          child: _isSendingSms
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  _countdown > 0
                                      ? '${_countdown}s'
                                      : '获取验证码',
                                  style: const TextStyle(fontSize: 13),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── 激活码 ──
                  _buildTextField(
                    fieldKey: 'activation',
                    controller: _activationCodeController,
                    focusNode: _activationCodeFocus,
                    label: '激活码',
                    icon: Icons.vpn_key_outlined,
                  ),
                  const SizedBox(height: 14),

                  // ── 用户协议复选框 ──
                  _buildTermsCheckbox(isDark),
                  const SizedBox(height: 16),

                  // ── 错误提示 ──
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

                  // ── 注册按钮 ──
                  SizedBox(
                    width: double.infinity,
                    height: 44,
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
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '注 册',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── 去登录链接 ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '已有账号？',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 13,
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Text(
                            '去登录',
                            style: TextStyle(
                              color: MyTheme.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }

  Widget _buildTermsCheckbox(bool isDark) {
    return AnimatedBuilder(
      animation:
          _shakeControllers['terms'] ?? const AlwaysStoppedAnimation(0),
      builder: (context, child) {
        final shake = _shakeControllers['terms'];
        final dx = shake == null
            ? 0.0
            : math.sin(shake.value * math.pi * 4) * 6 * (1 - shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: _agreedToTerms,
              activeColor: MyTheme.accent,
              // 桌面端缩小 checkbox 尺寸以更贴合桌面 UI 密度
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) =>
                  setState(() => _agreedToTerms = val ?? false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Wrap(
                children: [
                  Text(
                    '我已阅读并同意',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  _buildLinkText(
                    label: '《用户协议》',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const terms_pages.TermsOfServicePage(),
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
                  _buildLinkText(
                    label: '《隐私政策》',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const privacy_pages.PrivacyPolicyPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 带鼠标手型光标的超链接文字（桌面端必要）
  Widget _buildLinkText(
      {required String label, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: MyTheme.accent),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String fieldKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    // 桌面端不传 keyboardType（无虚拟键盘），保留参数兼容性
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        focusNode,
        if (_shakeControllers[fieldKey] != null) _shakeControllers[fieldKey]!,
      ]),
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;
        final isInvalid = _invalidFields[fieldKey] == true;
        final shake = _shakeControllers[fieldKey];
        final dx = shake == null
            ? 0.0
            : math.sin(shake.value * math.pi * 4) * 6 * (1 - shake.value);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscure,
            // 桌面端：仅在明确需要时传入 keyboardType
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            // 桌面端：Enter 键移至下一个焦点
            onSubmitted: (_) =>
                FocusScope.of(context).nextFocus(),
            onChanged: (value) {
              if ((value.isNotEmpty || value.trim().isNotEmpty) &&
                  _invalidFields[fieldKey] == true) {
                _clearFieldError(fieldKey);
              }
              if (onChanged != null) onChanged(value);
            },
            style: const TextStyle(fontSize: 14),
            // 桌面端使用更紧凑的视觉密度
            decoration: InputDecoration(
              labelText: hasFocus ? label : null,
              hintText: hasFocus ? null : label,
              floatingLabelBehavior: hasFocus
                  ? FloatingLabelBehavior.always
                  : FloatingLabelBehavior.never,
              labelStyle:
                  TextStyle(color: Colors.grey.shade600, fontSize: 14),
              hintStyle:
                  TextStyle(color: Colors.grey.shade500, fontSize: 14),
              floatingLabelStyle: TextStyle(
                color: MyTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                backgroundColor:
                    Theme.of(context).scaffoldBackgroundColor,
              ),
              prefixIcon: Icon(
                icon,
                size: 18,
                color: isInvalid ? Colors.red : Colors.grey.shade500,
              ),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color:
                        isInvalid ? Colors.red : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isInvalid ? Colors.red : MyTheme.accent,
                  width: 1.5,
                ),
              ),
              // 桌面端减小内边距，与桌面 UI 密度保持一致
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
              isDense: true,
            ),
          ),
        );
      },
    );
  }
}
