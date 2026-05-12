import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'login_tab_page.dart';
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;

/// 桌面端注册页面
class DesktopRegisterPage extends StatefulWidget {
  const DesktopRegisterPage({Key? key}) : super(key: key);

  @override
  State<DesktopRegisterPage> createState() => _DesktopRegisterPageState();
}

class _DesktopRegisterPageState extends State<DesktopRegisterPage>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _activationCodeController = TextEditingController(text: 'X99E-VDEY-TEFV-P7JS');
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
    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        const windowSize = Size(460, 680);
        await windowManager.setMinimumSize(windowSize);
        await windowManager.setResizable(false);
        await windowManager.setSize(windowSize);
        await windowManager.center();
      });
    }
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
    if (value.length < 1 || value.length > 20) return false;
    return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(value);
  }

  String? _validatePasswordFormat(String value) {
    if (value.isEmpty) return null;
    if (value.length < 6 || value.length > 20) {
      return translate('password_length_tip');
    }
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) {
      return translate('password_letter_digit_tip');
    }
    return null;
  }

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _setFieldError('phone', _phoneFocus, translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      _setFieldError('phone', _phoneFocus, translate('phone_must_be_11_digits'));
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
       SnackBar(content: translate('sms_code_sent')),
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
      _setFieldError('username', _usernameFocus, translate('please_enter_username'));
      return;
    }
    if (!_isUsernameValid(username)) {
      _setFieldError('username', _usernameFocus, translate('username_format_tip'));
      return;
    }
    if (password.isEmpty) {
      _setFieldError('password', _passwordFocus, translate('please_enter_password'));
      return;
    }
    if (!_isPasswordValid(password)) {
      _setFieldError('password', _passwordFocus, translate('password_format_tip'));
      return;
    }
    if (password != confirmPassword) {
      _setFieldError('confirmPassword', _confirmPasswordFocus, translate('password_not_match'));
      return;
    }
    if (phone.isEmpty) {
      _setFieldError('phone', _phoneFocus, translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      _setFieldError('phone', _phoneFocus, translate('phone_must_be_11_digits'));
      return;
    }
    if (smsCode.isEmpty) {
      _setFieldError('sms', _smsCodeFocus, translate('please_enter_sms_code'));
      return;
    }
    if (activationCode.isEmpty) {
      _setFieldError('activation', _activationCodeFocus, translate('please_enter_activation_code'));
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _errorMsg = translate('please_agree_terms'));
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
            content: Text(translate('register_success')),
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

    void handleEnter() {
      if (_isLoading) return;
      _register();
    }

    // ── 桌面端：居中卡片布局，不使用 AppBar / SafeArea ──
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): handleEnter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): handleEnter,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1D23) : Colors.white,
      body: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SizedBox(
              width: 380, // 桌面固定宽度，与登录页一致
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // ── 标题区：居中 Logo + 页面名（与登录页风格一致），关闭按钮叠加右上角 ──
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 28,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            translate('register_title'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),

                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 用户名 ──
                  _buildTextField(
                    fieldKey: 'username',
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    label: translate('Username'),
                    icon: Icons.person_outline,
                    inputFormatters: [
                      _UsernameInputFormatter(),
                      LengthLimitingTextInputFormatter(20),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── 密码 ──
                  _buildTextField(
                    fieldKey: 'password',
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    label: translate('Password'),
                    icon: Icons.lock_outline,
                    obscure: _obscurePassword,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\u4e00-\u9fff]')),
                    ],
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
                  const SizedBox(height: 10),

                  // ── 确认密码 ──
                  _buildTextField(
                    fieldKey: 'confirmPassword',
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocus,
                    label: translate('field_confirm_password'),
                    icon: Icons.lock_outline,
                    obscure: _obscureConfirm,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\u4e00-\u9fff]')),
                    ],
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
                  const SizedBox(height: 10),

                  // ── 手机号 ──
                  _buildTextField(
                    fieldKey: 'phone',
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    label: translate('Phone Number'),
                    icon: Icons.phone_android,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    // 桌面端不设置 keyboardType，避免弹出虚拟键盘提示
                  ),
                  const SizedBox(height: 10),

                  // ── 验证码 + 获取按钮 ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildTextField(
                          fieldKey: 'sms',
                          controller: _smsCodeController,
                          focusNode: _smsCodeFocus,
                          label: translate('Verification code'),
                          icon: Icons.sms_outlined,
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
                            backgroundColor: const Color(0xFF7C3AED),
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
                                      : translate('get_sms_code') ,
                                  style: const TextStyle(fontSize: 13),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── 激活码 ──
                  _buildTextField(
                    fieldKey: 'activation',
                    controller: _activationCodeController,
                    focusNode: _activationCodeFocus,
                    label: translate('field_activation_code'),
                    icon: Icons.vpn_key_outlined,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _register(),
                  ),
                  const SizedBox(height: 10),

                  // ── 用户协议复选框 ──
                  _buildTermsCheckbox(isDark),
                  const SizedBox(height: 16),

                  // ── 错误提示 ──
                  if (_errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
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
                        backgroundColor: isDark
                            ? const Color(0xFF6D28D9)
                            : const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        overlayColor: isDark
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF6D28D9),
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
                          : Text(
                              translate('register_btn'),
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 去登录链接 ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        translate('already_have_account'),
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
                            translate('go_to_login'),
                            style: const TextStyle(
                              color: Color(0xFF7C3AED),
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
    ))));
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
              activeColor: const Color(0xFF7C3AED),
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
                    translate('terms_agreed_prefix'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  _buildLinkText(
                    label: translate('terms_link_label'),
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) =>
                            const LoginTabPage(showBackButton: true, child: terms_pages.TermsOfServicePage()),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    ),
                  ),
                  Text(
                    translate('and_connector'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  _buildLinkText(
                    label: translate('privacy_link_label'),
                    onTap: () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) =>
                            const LoginTabPage(showBackButton: true, child: privacy_pages.PrivacyPolicyPage()),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
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
          style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED)),
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
    ValueChanged<String>? onSubmitted, // ← 新增：支持可覆盖的提交操作
    TextInputAction? textInputAction,  // ← 新增：支持回车键行为自定义
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
            // 桌面：配置指定的 action 和 onSubmitted
            textInputAction: textInputAction ?? TextInputAction.next,
            onSubmitted: onSubmitted ?? (_) => FocusScope.of(context).nextFocus(),
            onChanged: (value) {
              if ((value.isNotEmpty || value.trim().isNotEmpty) &&
                  _invalidFields[fieldKey] == true) {
                _clearFieldError(fieldKey);
              }
              if (onChanged != null) onChanged(value);
            },
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              labelText: hasFocus ? label : null,
              hintText: hasFocus ? null : label,
              floatingLabelBehavior: hasFocus
                  ? FloatingLabelBehavior.always
                  : FloatingLabelBehavior.never,
              labelStyle:
                  TextStyle(color: Colors.grey.shade600, fontSize: 15),
              hintStyle:
                  TextStyle(color: Colors.grey.shade600, fontSize: 15),
              floatingLabelStyle: TextStyle(
                color: const Color(0xFF7C3AED),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                backgroundColor:
                    Theme.of(context).scaffoldBackgroundColor,
              ),
              prefixIcon: Icon(
                icon,
                size: 20,
                color: isInvalid ? Colors.red : null,
              ),
              suffixIcon: suffix,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color:
                        isInvalid ? Colors.red : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isInvalid ? Colors.red : const Color(0xFF7C3AED),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              isDense: false,
            ),
          ),
        );
      },
    );
  }
}
/// 用户名输入过滤器：只允许英文、数字和下划线，不允许中文。
/// IME 组字期间不干预，避免输入法叠字问题。
class _UsernameInputFormatter extends TextInputFormatter {
  static final _allowedPattern = RegExp(r'[^A-Za-z0-9_]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing != TextRange.empty) return newValue;

    final filtered = newValue.text.replaceAll(_allowedPattern, '');
    if (filtered == newValue.text) return newValue;

    return newValue.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
      composing: TextRange.empty,
    );
  }
}