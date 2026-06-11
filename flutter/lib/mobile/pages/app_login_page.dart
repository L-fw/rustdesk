import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/mobile/pages/app_register_page.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;

/// 应用登录页面
class AppLoginPage extends StatefulWidget {
  const AppLoginPage({Key? key}) : super(key: key);

  @override
  State<AppLoginPage> createState() => _AppLoginPageState();
}

class _AppLoginPageState extends State<AppLoginPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 账号密码登录
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  // 手机验证码登录
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _smsCodeFocus = FocusNode();
  int _countdown = 0;
  Timer? _countdownTimer;

  bool _isLoading = false;
  String? _errorMsg;

  final _authService = AppAuthService();

  bool _agreedToTerms = false;
  final String _agreedTermsVersionKey = 'agreed_terms_version';
  final String _agreedPrivacyVersionKey = 'agreed_privacy_version';
  final String _currentTermsVersion = terms_pages.termsOfServiceVersion;
  final String _currentPrivacyVersion = privacy_pages.privacyPolicyVersion;
  final String _accountHistoryKey = 'app_login_accounts';
  final String _lastAccountKey = 'app_login_last_account';
  final String _lastPhoneKey = 'app_login_last_phone';
  final String _rememberPasswordEnabledKey = 'app_login_remember_password_enabled';
  final Map<String, AnimationController> _shakeControllers = {};
  final Map<String, bool> _invalidFields = {};
  final List<String> _accountHistory = [];
  bool _rememberPassword = false;

  @override
  void initState() {
    super.initState();
    _shakeControllers['username'] = _createShakeController();
    _shakeControllers['password'] = _createShakeController();
    _shakeControllers['phone'] = _createShakeController();
    _shakeControllers['sms'] = _createShakeController();
    _shakeControllers['terms'] = _createShakeController();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _errorMsg = null);
      }
    });
    // Check local storage for agreed terms version
    _agreedToTerms = bind.mainGetLocalOption(key: _agreedTermsVersionKey) == _currentTermsVersion &&
                     bind.mainGetLocalOption(key: _agreedPrivacyVersionKey) == _currentPrivacyVersion;
    _loadAccountHistory();
    _loadPhoneHistory();
    _loadRememberedPasswordForUser(_usernameController.text.trim());
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _shakeControllers.values) {
      controller.dispose();
    }
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();
    _smsCodeFocus.dispose();
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

  bool _isUsernameValid(String value) {
    if (value.length < 1 || value.length > 20) return false;
    return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(value);
  }

  /// Check if an error indicates the bound activation code is unusable
  /// (expired / invalid / disabled) and can be replaced by entering a new one.
  bool _isActivationCodeError(String error) {
    return error == translate('activation_code_expired_error') ||
        error == translate('server_invalid_activation_code') ||
        error == translate('server_activation_code_disabled');
  }

  /// Check if an error message is password-related (language-agnostic)
  bool _isPasswordError(String error) {
    final lower = error.toLowerCase();
    return error.contains('密码') ||
        lower.contains('password') ||
        error == translate('server_wrong_password') ||
        error == translate('server_wrong_credentials');
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

  void _loadAccountHistory() {
    final raw = bind.mainGetLocalOption(key: _accountHistoryKey);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _accountHistory
            ..clear()
            ..addAll(decoded
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty));
        }
      } catch (_) {}
    }
    final lastAccount = bind.mainGetLocalOption(key: _lastAccountKey).trim();
    final initial = lastAccount.isNotEmpty
        ? lastAccount
        : (_accountHistory.isNotEmpty ? _accountHistory.first : '');
    if (initial.isNotEmpty && _usernameController.text.isEmpty) {
      _usernameController.text = initial;
    }
  }

  void _loadPhoneHistory() {
    final lastPhone = bind.mainGetLocalOption(key: _lastPhoneKey).trim();
    if (lastPhone.isNotEmpty && _phoneController.text.isEmpty) {
      _phoneController.text = lastPhone;
    }
  }

  void _rememberPhone(String phone) {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    bind.mainSetLocalOption(key: _lastPhoneKey, value: normalized);
  }

  Future<void> _loadRememberedPasswordForUser(String username) async {
    final enabled =
        bind.mainGetLocalOption(key: _rememberPasswordEnabledKey) == 'Y';
    if (mounted) {
      setState(() => _rememberPassword = enabled);
    }
    if (!enabled || username.isEmpty) {
      return;
    }
    final remembered = await _authService.getRememberedPassword(username);
    if (!mounted) return;
    _passwordController.text = remembered ?? '';
    if ((_passwordController.text.isNotEmpty) &&
        _invalidFields['password'] == true) {
      _clearFieldError('password');
    }
  }

  void _rememberAccount(String username) {
    final normalized = username.trim();
    if (normalized.isEmpty) return;
    _accountHistory.removeWhere((e) => e == normalized);
    _accountHistory.insert(0, normalized);
    if (_accountHistory.length > 5) {
      _accountHistory
        ..removeRange(5, _accountHistory.length);
    }
    bind.mainSetLocalOption(
        key: _accountHistoryKey, value: jsonEncode(_accountHistory));
    bind.mainSetLocalOption(key: _lastAccountKey, value: normalized);
  }

  void _selectAccount(String username) {
    _usernameController.text = username;
    _clearFieldError('username');
    bind.mainSetLocalOption(key: _lastAccountKey, value: username);
    _loadRememberedPasswordForUser(username);
    if (!_usernameFocus.hasFocus) {
      _usernameFocus.requestFocus();
    }
    setState(() {});
  }

  Widget? _buildAccountSwitcher() {
    if (_accountHistory.isEmpty) return null;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
      onSelected: _selectAccount,
      itemBuilder: (context) => _accountHistory
          .map((account) => PopupMenuItem<String>(
                value: account,
                child: Text(account),
              ))
          .toList(),
    );
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
      _isLoading = true;
      _errorMsg = null;
    });
    final error = await _authService.sendSmsCode(phone: phone);
    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        setState(() => _errorMsg = error);
      } else {
        _startCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translate('sms_code_sent'))),
        );
      }
    }
  }

  Future<String?> _showActivationCodeDialog() async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(translate('activation_code_expired_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(translate('please_enter_new_activation_code')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: translate('new_activation_code_label'),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(translate('Cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setStateDialog(() => errorText = translate('please_enter_activation_code'));
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(translate('OK')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    final trimmed = result?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _handlePasswordLoginSuccess(
      String username, String password) async {
    if (_rememberPassword) {
      await _authService.saveRememberedPassword(
        username: username,
        password: password,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
    } else {
      await _authService.clearRememberedPassword(username);
    }
    _rememberAccount(username);
    bind.mainSetLocalOption(
        key: _agreedTermsVersionKey, value: _currentTermsVersion);
    bind.mainSetLocalOption(
        key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
    _goToHome();
  }

  Future<void> _loginWithPassword() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      _setFieldError('username', _usernameFocus, translate('please_enter_username'));
      return;
    }
    if (!_isUsernameValid(username)) {
      _setFieldError('username', _usernameFocus, translate('username_format_tip'));
      return;
    }
    if (password.isEmpty) {
      _setFieldError('password', _passwordFocus, translate('Please enter your password'));
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

    final error = await _authService.login(
      username: username,
      password: password,
      agreedTermsVersion: _currentTermsVersion,
      agreedPrivacyVersion: _currentPrivacyVersion,
      agreedTime: DateTime.now().toIso8601String(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        if (_isActivationCodeError(error)) {
          final newCode = await _showActivationCodeDialog();
          if (!mounted) return;
          if (newCode == null) {
            setState(() => _errorMsg = error);
            return;
          }
          setState(() {
            _isLoading = true;
            _errorMsg = null;
          });
          final retryError = await _authService.login(
            username: username,
            password: password,
            activationCode: newCode,
            agreedTermsVersion: _currentTermsVersion,
            agreedPrivacyVersion: _currentPrivacyVersion,
            agreedTime: DateTime.now().toIso8601String(),
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
          if (retryError != null) {
            if (_isPasswordError(retryError)) {
              _setFieldError('password', _passwordFocus, retryError);
            } else {
              setState(() => _errorMsg = retryError);
            }
          } else {
            await _handlePasswordLoginSuccess(username, password);
          }
          return;
        }
        if (_isPasswordError(error)) {
          _setFieldError('password', _passwordFocus, error);
        } else {
          setState(() => _errorMsg = error);
        }
      } else {
        await _handlePasswordLoginSuccess(username, password);
      }
    }
  }

  Future<void> _loginWithSms() async {
    final phone = _phoneController.text.trim();
    final code = _smsCodeController.text.trim();

    if (phone.isEmpty) {
      _setFieldError('phone', _phoneFocus, translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      _setFieldError('phone', _phoneFocus, translate('phone_must_be_11_digits'));
      return;
    }
    if (code.isEmpty) {
      _setFieldError('sms', _smsCodeFocus, translate('please_enter_sms_code'));
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

    final error = await _authService.smsLogin(
      phone: phone, 
      code: code,
      agreedTermsVersion: _currentTermsVersion,
      agreedPrivacyVersion: _currentPrivacyVersion,
      agreedTime: DateTime.now().toIso8601String(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) {
        if (_isActivationCodeError(error)) {
          final newCode = await _showActivationCodeDialog();
          if (!mounted) return;
          if (newCode == null) {
            setState(() => _errorMsg = error);
            return;
          }
          setState(() {
            _isLoading = true;
            _errorMsg = null;
          });
          final retryError = await _authService.smsLogin(
            phone: phone,
            code: code,
            activationCode: newCode,
            agreedTermsVersion: _currentTermsVersion,
            agreedPrivacyVersion: _currentPrivacyVersion,
            agreedTime: DateTime.now().toIso8601String(),
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
          if (retryError != null) {
            setState(() => _errorMsg = retryError);
          } else {
            _rememberPhone(phone);
            bind.mainSetLocalOption(
                key: _agreedTermsVersionKey, value: _currentTermsVersion);
            bind.mainSetLocalOption(
                key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
            _goToHome();
          }
          return;
        }
        setState(() => _errorMsg = error);
      } else {
        _rememberPhone(phone);
        bind.mainSetLocalOption(key: _agreedTermsVersionKey, value: _currentTermsVersion);
        bind.mainSetLocalOption(key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
        _goToHome();
      }
    }
  }

  void _goToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage()),
      (route) => false,
    );
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppRegisterPage()),
    );
  }

  Future<void> _showForgotPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ForgotPasswordDialog(),
    );
    if (!mounted) return;
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translate('password_reset_success'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1D23) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & App Name
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/about_logo.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  bind.mainGetAppNameSync(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 20),

                // Tab Bar
                Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor:
                        isDark ? Colors.white60 : Colors.black54,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 13),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(text: translate('tab_account_login')),
                      Tab(text: translate('tab_phone_login')),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Tab Content
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _tabController.index == 0
                        ? Container(
                            key: const ValueKey(0),
                            child: _buildPasswordLoginTab(),
                          )
                        : Container(
                            key: const ValueKey(1),
                            child: _buildSmsLoginTab(),
                          ),
                  ),
                ),

                // Error Message
                if (_errorMsg != null) ...[
                  const SizedBox(height: 8),
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
                ],

                const SizedBox(height: 16),

                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      translate('no_account_prompt'),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 13,
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _goToRegister,
                        child: Text(
                          translate('register_now'),
                          style: TextStyle(
                            color: const Color(0xFF7C3AED),
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
    );
  }

  Widget _buildPasswordLoginTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Username
        _buildTextField(
          fieldKey: 'username',
          controller: _usernameController,
          focusNode: _usernameFocus,
          label: translate('Username'),
          icon: Icons.person_outline,
          suffix: _buildAccountSwitcher(),
          inputFormatters: [
            _UsernameInputFormatter(),
            LengthLimitingTextInputFormatter(20),
          ],
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 10),
        // Password
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loginWithPassword(),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _rememberPassword,
                activeColor: const Color(0xFF7C3AED),
                onChanged: (val) {
                  final next = val ?? false;
                  setState(() => _rememberPassword = next);
                  bind.mainSetLocalOption(
                      key: _rememberPasswordEnabledKey,
                      value: next ? 'Y' : 'N');
                  if (!next) {
                    _authService
                        .clearRememberedPassword(_usernameController.text.trim());
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              translate('remember_password'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildTermsCheckbox(isDark),
        const SizedBox(height: 12),
        // Login Button
        _buildLoginButton(onPressed: _loginWithPassword),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _showForgotPassword,
              child: Text(
                translate('Forget Password'),
                style: TextStyle(
                  color: const Color(0xFF7C3AED),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
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
              activeColor: const Color(0xFF7C3AED),
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
                    translate('terms_agreed_prefix'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const terms_pages.TermsOfServicePage(),
                        ),
                      );
                    },
                    child: Text(
                      translate('terms_link_label'),
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF7C3AED),
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
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const privacy_pages.PrivacyPolicyPage(),
                        ),
                      );
                    },
                    child: Text(
                      translate('privacy_link_label'),
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF7C3AED),
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

  Widget _buildSmsLoginTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Phone
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
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _smsCodeFocus.requestFocus(),
        ),
        const SizedBox(height: 10),
        // SMS Code + Send Button
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
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loginWithSms(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed:
                    (_countdown > 0 || _isLoading) ? null : _sendSmsCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                ),
                child: Text(
                  _countdown > 0 ? '${_countdown}s' : translate('get_sms_code'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildTermsCheckbox(isDark),
        const SizedBox(height: 12),
        // Login Button
        _buildLoginButton(onPressed: _loginWithSms),
      ],
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
    return AnimatedBuilder(
      animation: Listenable.merge([
        focusNode,
        if (_shakeControllers[fieldKey] != null) _shakeControllers[fieldKey]!,
      ]),
      builder: (context, _) {
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
            inputFormatters: inputFormatters,
            textInputAction: textInputAction ?? TextInputAction.done,
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
              prefixIcon: Icon(icon,
                  size: 20, color: isInvalid ? Colors.red : null),
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

  Widget _buildLoginButton({required VoidCallback onPressed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF6D28D9) : const Color(0xFF7C3AED);
    const textColor = Colors.white;
    final overlayColor = isDark
        ? const Color(0xFF7C3AED)
        : const Color(0xFF6D28D9);

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          overlayColor: overlayColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: textColor,
                ),
              )
            : Text(
                translate('login_btn'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AppAuthService();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isSendingSms = false;
  String? _errorMsg;
  String? _passwordFormatError;
  String? _confirmPasswordError;

  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _smsCodeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = translate('phone_must_be_11_digits'));
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

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final smsCode = _smsCodeController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (phone.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_phone'));
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = translate('phone_must_be_11_digits'));
      return;
    }
    if (smsCode.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_sms_code'));
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMsg = translate('please_enter_new_password'));
      return;
    }
    if (password.length < 6 || password.length > 20) {
      setState(() => _errorMsg = translate('password_length_tip'));
      return;
    }
    final hasLetter = password.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = password.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) {
      setState(() => _errorMsg = translate('password_letter_digit_tip'));
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMsg = translate('password_not_match'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final error = await _authService.resetPassword(
      phone: phone,
      smsCode: smsCode,
      newPassword: password,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      setState(() => _errorMsg = error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Text(translate('Forget Password')),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: InputDecoration(
                  labelText: translate('Phone Number'),
                  prefixIcon: const Icon(Icons.phone_android, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _smsCodeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: translate('Verification code'),
                        prefixIcon: const Icon(Icons.sms_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_countdown > 0 || _isSendingSms || _isLoading)
                          ? null
                          : _sendSmsCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        elevation: 0,
                      ),
                      child: Text(
                        _countdown > 0 ? '${_countdown}s' : translate('get_sms_code'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\u4e00-\u9fff]')),
                ],
                onChanged: (value) {
                  final error = _validatePasswordFormat(value);
                  if (error != _passwordFormatError) {
                    setState(() => _passwordFormatError = error);
                  }
                },
                decoration: InputDecoration(
                  labelText: translate('new_password_label'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
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
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\u4e00-\u9fff]')),
                ],
                onChanged: (value) {
                  final error = (value.isNotEmpty && value != _passwordController.text)
                      ? translate('password_not_match')
                      : null;
                  if (error != _confirmPasswordError) {
                    setState(() => _confirmPasswordError = error);
                  }
                },
                decoration: InputDecoration(
                  labelText: translate('confirm_new_password_label'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirmPassword =
                          !_obscureConfirmPassword);
                    },
                  ),
                ),
              ),
              if (_confirmPasswordError != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _confirmPasswordError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  translate('sms_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(translate('Cancel')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(translate('confirm_reset_btn')),
        ),
      ],
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