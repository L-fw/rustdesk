import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/consts.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;

/// 主题色：与桌面端登录/注册设计稿一致的蓝色系
const Color _kPrimaryColor = Color(0xFF2E6FF2);
const List<Color> _kButtonGradient = [Color(0xFF2D63F0), Color(0xFF5B9BFF)];

/// 应用注册页面
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

  // 输入框吞掉不规范字符时的提示（延后到帧末，避免在过滤过程中 setState 并被 onChanged 清除）
  void _onCharRejected(String key, FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setFieldError(key, node, translate('please_enter_valid_characters'));
    });
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
       SnackBar(content: Text(translate('sms_code_sent'))),
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
          SnackBar(
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

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1D23) : Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 标题区：与桌面端注册卡片一致 ──
                Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _kPrimaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_outlined,
                        size: 28,
                        color: _kPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      translate('register_title'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: isDark ? Colors.white : const Color(0xFF1B2233),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      translate('register_welcome_subtitle')
                          .replaceFirst('{}', bind.mainGetAppNameSync()),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? const Color(0xFFA5ABB3)
                              : const Color(0xFF8A93A6)),
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
                const SizedBox(height: 12),

                // ── 手机号 ──
                _buildTextField(
                  fieldKey: 'phone',
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  label: translate('Phone Number'),
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                const SizedBox(height: 12),

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
                        icon: Icons.verified_user_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: (_countdown > 0 || _isSendingSms)
                            ? null
                            : _sendSmsCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF1E2A3D)
                              : const Color(0xFFE8F0FF),
                          foregroundColor: _kPrimaryColor,
                          disabledBackgroundColor: Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 0,
                        ),
                        child: _isSendingSms
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kPrimaryColor),
                              )
                            : Text(
                                _countdown > 0
                                    ? '${_countdown}s'
                                    : translate('get_sms_code'),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 密码 ──
                _buildTextField(
                  fieldKey: 'password',
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  label: translate('Password'),
                  icon: Icons.lock_outline,
                  obscure: _obscurePassword,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[一-鿿]')),
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
                    FilteringTextInputFormatter.deny(RegExp(r'[一-鿿]')),
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
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // ── 激活码 ──
                _buildTextField(
                  fieldKey: 'activation',
                  controller: _activationCodeController,
                  focusNode: _activationCodeFocus,
                  label: translate('field_activation_code'),
                  icon: Icons.vpn_key_outlined,
                  inputFormatters: [_UpperCaseTextInputFormatter()],
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
                _buildRegisterButton(),
                const SizedBox(height: 16),
                Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0x14FFFFFF)
                        : const Color(0x14000000)),
                const SizedBox(height: 14),

                // ── 去登录链接 ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('already_have_account'),
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFA5ABB3)
                            : const Color(0xFF8A93A6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        translate('go_to_login'),
                        style: const TextStyle(
                          color: _kPrimaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    const textColor = Colors.white;
    return Opacity(
      opacity: _isLoading ? 0.7 : 1.0,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: _kButtonGradient,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: _kPrimaryColor.withOpacity(0.32),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: _isLoading ? null : _register,
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: textColor),
                    )
                  : Text(
                      translate('register_btn'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTermsCheckbox(bool isDark) {
    return AnimatedBuilder(
      animation: _shakeControllers['terms'] ?? const AlwaysStoppedAnimation(0),
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
              activeColor: _kPrimaryColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                setState(() => _agreedToTerms = val ?? false);
              },
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
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(kTermsOfServiceUrl),
                        mode: LaunchMode.externalApplication),
                    child: Text(
                      translate('terms_link_label'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kPrimaryColor,
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
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(kPrivacyPolicyUrl),
                        mode: LaunchMode.externalApplication),
                    child: Text(
                      translate('privacy_link_label'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kPrimaryColor,
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

  Widget _buildTextField({
    required String fieldKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextInputAction? textInputAction,
  }) {
    // 为字符过滤器包一层：当不规范字符被吞掉时，复用错误提示框提醒用户。
    // 长度限制与大小写转换不属于"吞字"，不包装，避免误触发错误提示。
    final effectiveFormatters = inputFormatters
        ?.map((f) => f is LengthLimitingTextInputFormatter ||
                f is _UpperCaseTextInputFormatter
            ? f
            : _RejectNotifyingFormatter(
                f, () => _onCharRejected(fieldKey, focusNode)))
        .toList();
    return AnimatedBuilder(
      animation: Listenable.merge([
        focusNode,
        if (_shakeControllers[fieldKey] != null) _shakeControllers[fieldKey]!,
      ]),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
            keyboardType: keyboardType,
            inputFormatters: effectiveFormatters,
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
              hintText: label,
              floatingLabelBehavior: FloatingLabelBehavior.never,
              hintStyle:
                  TextStyle(color: Colors.grey.shade500, fontSize: 15),
              prefixIcon: Icon(
                icon,
                size: 20,
                color: isInvalid
                    ? Colors.red
                    : (hasFocus
                        ? _kPrimaryColor
                        : (isDark
                            ? const Color(0xFF8A9099)
                            : const Color(0xFF9AA3B2))),
              ),
              suffixIcon: suffix,
              filled: true,
              fillColor: isInvalid
                  ? (isDark
                      ? const Color(0xFF3A2626)
                      : const Color(0xFFFFF5F5))
                  : (isDark
                      ? const Color(0xFF2C2D34)
                      : const Color(0xFFF6F8FB)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(
                    color: isInvalid
                        ? Colors.red
                        : (isDark
                            ? const Color(0xFF34353C)
                            : const Color(0xFFE3E8F0))),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(
                  color: isInvalid ? Colors.red : _kPrimaryColor,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              isDense: true,
            ),
          ),
        );
      },
    );
  }
}

/// 包装字符过滤器：当内部过滤器吞掉不规范字符（导致文本变化）时触发回调，
/// 用于复用页面原有的错误提示框提醒用户。不改变过滤结果本身。
class _RejectNotifyingFormatter extends TextInputFormatter {
  _RejectNotifyingFormatter(this.inner, this.onReject);

  final TextInputFormatter inner;
  final VoidCallback onReject;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final result = inner.formatEditUpdate(oldValue, newValue);
    if (result.text != newValue.text) {
      onReject();
    }
    return result;
  }
}

/// 激活码输入格式化：小写字母实时转换为大写显示。
/// 仅转换 ASCII a-z（长度不变，光标位置不受影响）；
/// IME 组字期间不干预，避免输入法叠字问题。
class _UpperCaseTextInputFormatter extends TextInputFormatter {
  static final _lowerCasePattern = RegExp(r'[a-z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing != TextRange.empty) return newValue;

    final upper = newValue.text
        .replaceAllMapped(_lowerCasePattern, (m) => m[0]!.toUpperCase());
    if (upper == newValue.text) return newValue;

    return newValue.copyWith(text: upper);
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
