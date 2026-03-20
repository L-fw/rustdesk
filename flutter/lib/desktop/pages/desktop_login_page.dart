import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/app_auth_service.dart';
import 'package:flutter_hbb/desktop/pages/desktop_register_page.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'desktop_tab_page.dart';
import 'login_tab_page.dart';
import 'privacy_policy.dart' as privacy_pages;
import 'terms_of_service.dart' as terms_pages;

/// 应用登录页面（Desktop）
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
  final String _rememberPasswordEnabledKey =
      'app_login_remember_password_enabled';
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
    _agreedToTerms =
        bind.mainGetLocalOption(key: _agreedTermsVersionKey) ==
                _currentTermsVersion &&
            bind.mainGetLocalOption(key: _agreedPrivacyVersionKey) ==
                _currentPrivacyVersion;
    _loadAccountHistory();
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
    return RegExp(r'^[A-Za-z0-9\u4e00-\u9fff]+$').hasMatch(value);
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
    final lastAccount =
        bind.mainGetLocalOption(key: _lastAccountKey).trim();
    final initial = lastAccount.isNotEmpty
        ? lastAccount
        : (_accountHistory.isNotEmpty ? _accountHistory.first : '');
    if (initial.isNotEmpty && _usernameController.text.isEmpty) {
      _usernameController.text = initial;
    }
  }

  Future<void> _loadRememberedPasswordForUser(String username) async {
    final enabled =
        bind.mainGetLocalOption(key: _rememberPasswordEnabledKey) == 'Y';
    if (mounted) setState(() => _rememberPassword = enabled);
    if (!enabled || username.isEmpty) return;
    final remembered = await _authService.getRememberedPassword(username);
    if (!mounted) return;
    _passwordController.text = remembered ?? '';
    if (_passwordController.text.isNotEmpty &&
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
      _accountHistory.removeRange(5, _accountHistory.length);
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
    if (!_usernameFocus.hasFocus) _usernameFocus.requestFocus();
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
      _setFieldError('phone', _phoneFocus, '请输入手机号');
      return;
    }
    if (phone.length != 11) {
      _setFieldError('phone', _phoneFocus, '手机号必须为11位数字');
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
          const SnackBar(content: Text('验证码已发送')),
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
              title: const Text('激活码已失效'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('请输入新的激活码继续使用'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: '新激活码',
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setStateDialog(() => errorText = '请输入激活码');
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确认'),
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
    if (!_agreedToTerms) {
      setState(() => _errorMsg = '请先阅读并同意《用户协议》与《隐私政策》');
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
        if (error == '激活码已过期') {
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
            if (retryError.contains('密码')) {
              _setFieldError('password', _passwordFocus, retryError);
            } else {
              setState(() => _errorMsg = retryError);
            }
          } else {
            await _handlePasswordLoginSuccess(username, password);
          }
          return;
        }
        if (error.contains('密码')) {
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
      _setFieldError('phone', _phoneFocus, '请输入手机号');
      return;
    }
    if (phone.length != 11) {
      _setFieldError('phone', _phoneFocus, '手机号必须为11位数字');
      return;
    }
    if (code.isEmpty) {
      _setFieldError('sms', _smsCodeFocus, '请输入验证码');
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
        if (error == '激活码已过期') {
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
        bind.mainSetLocalOption(
            key: _agreedTermsVersionKey, value: _currentTermsVersion);
        bind.mainSetLocalOption(
            key: _agreedPrivacyVersionKey, value: _currentPrivacyVersion);
        _goToHome();
      }
    }
  }

  void _goToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DesktopTabPage()),
      (route) => false,
    );
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const LoginTabPage(child: DesktopRegisterPage())),
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
        const SnackBar(content: Text('密码已重置，请使用新密码登录')),
      );
    }
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Desktop：全屏背景 + 居中固定宽度登录卡片
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1A1D23) : const Color(0xFFF0F2F5),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: SizedBox(
            width: 420, // 桌面固定宽度
            child: Card(
              elevation: isDark ? 4 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: isDark ? const Color(0xFF252830) : Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo & App Name
                    Icon(
                      Icons.connected_tv_rounded,
                      size: 56,
                      color: MyTheme.accent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      bind.mainGetAppNameSync(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '远程协助管理平台',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Tab Bar
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: MyTheme.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor:
                            isDark ? Colors.white60 : Colors.black54,
                        labelStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 14),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: '账号登录'),
                          Tab(text: '手机登录'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tab Content —— 桌面不限死高度，让内容自适应
                    SizedBox(
                      height: 268,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPasswordLoginTab(),
                          _buildSmsLoginTab(),
                        ],
                      ),
                    ),

                    // Error Message
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 8),
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
                                color: Colors.red, size: 18),
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
                    ],

                    const SizedBox(height: 20),

                    // Register Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '没有账号？',
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
                              '立即注册',
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
      ),
    );
  }

  // ─────────────────────── 密码登录 Tab ───────────────────────

  Widget _buildPasswordLoginTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _buildTextField(
          fieldKey: 'username',
          controller: _usernameController,
          focusNode: _usernameFocus,
          label: '用户名',
          icon: Icons.person_outline,
          suffix: _buildAccountSwitcher(),
          inputFormatters: [
            _UsernameInputFormatter(),
          ],
          // 桌面：Tab 键切换焦点
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        _buildTextField(
          fieldKey: 'password',
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: '密码',
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: Colors.grey,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          // 桌面：Enter 键直接登录
          onSubmitted: (_) => _loginWithPassword(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _rememberPassword,
                activeColor: MyTheme.accent,
                onChanged: (val) {
                  final next = val ?? false;
                  setState(() => _rememberPassword = next);
                  bind.mainSetLocalOption(
                      key: _rememberPasswordEnabledKey,
                      value: next ? 'Y' : 'N');
                  if (!next) {
                    _authService.clearRememberedPassword(
                        _usernameController.text.trim());
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '记住密码（7天）',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildTermsCheckbox(isDark),
        const SizedBox(height: 16),
        _buildLoginButton(onPressed: _loginWithPassword),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _showForgotPassword,
              child: Text(
                '忘记密码？',
                style: TextStyle(
                  color: MyTheme.accent,
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

  // ─────────────────────── 短信登录 Tab ───────────────────────

  Widget _buildSmsLoginTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _buildTextField(
          fieldKey: 'phone',
          controller: _phoneController,
          focusNode: _phoneFocus,
          label: '手机号',
          icon: Icons.phone_android,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          onSubmitted: (_) => _smsCodeFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
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
                keyboardType: TextInputType.number,
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
        const SizedBox(height: 28),
        _buildTermsCheckbox(isDark),
        const SizedBox(height: 16),
        _buildLoginButton(onPressed: _loginWithSms),
      ],
    );
  }

  // ─────────────────────── 公共 Widgets ───────────────────────

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
              activeColor: MyTheme.accent,
              onChanged: (val) =>
                  setState(() => _agreedToTerms = val ?? false),
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
                        color: isDark ? Colors.white54 : Colors.black54),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const terms_pages.TermsOfServicePage())),
                      child: Text('《用户协议》',
                          style:
                              TextStyle(fontSize: 12, color: MyTheme.accent)),
                    ),
                  ),
                  Text(
                    '与',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const privacy_pages.PrivacyPolicyPage())),
                      child: Text('《隐私政策》',
                          style:
                              TextStyle(fontSize: 12, color: MyTheme.accent)),
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
    ValueChanged<String>? onSubmitted, // ← 桌面新增：支持 Enter 提交
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
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            // 桌面：Tab 键跳转下一个输入框
            textInputAction: onSubmitted != null
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: onSubmitted,
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
                color: MyTheme.accent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                backgroundColor:
                    Theme.of(context).scaffoldBackgroundColor,
              ),
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
                  color: isInvalid ? Colors.red : MyTheme.accent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              isDense: false,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginButton({required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MyTheme.accent,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Text(
                '登 录',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  忘记密码 Dialog（desktop 版本，宽度限制 360）
// ═══════════════════════════════════════════════════════════

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
      setState(() => _errorMsg = '请输入手机号');
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = '手机号必须为11位数字');
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

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final smsCode = _smsCodeController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (phone.isEmpty) {
      setState(() => _errorMsg = '请输入手机号');
      return;
    }
    if (phone.length != 11) {
      setState(() => _errorMsg = '手机号必须为11位数字');
      return;
    }
    if (smsCode.isEmpty) {
      setState(() => _errorMsg = '请输入验证码');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMsg = '请输入新密码');
      return;
    }
    if (password.length < 6 || password.length > 20) {
      setState(() => _errorMsg = '密码需为6-20位字符');
      return;
    }
    final hasLetter = password.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = password.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) {
      setState(() => _errorMsg = '密码需包含字母和数字');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMsg = '两次密码输入不一致');
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
      title: const Text('忘记密码'),
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
                decoration: const InputDecoration(
                  labelText: '手机号',
                  prefixIcon: Icon(Icons.phone_android, size: 20),
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
                      decoration: const InputDecoration(
                        labelText: '验证码',
                        prefixIcon: Icon(Icons.sms_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          (_countdown > 0 || _isSendingSms || _isLoading)
                              ? null
                              : _sendSmsCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyTheme.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
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
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '新密码',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMsg!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '验证码会发送到你填写的手机号',
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
          onPressed:
              _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyTheme.accent,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('确认重置'),
        ),
      ],
    );
  }
}
/// 用户名输入过滤器：只允许中文、英文、数字。
/// IME 组字期间不干预，避免中文输入法叠字问题。
class _UsernameInputFormatter extends TextInputFormatter {
  static final _allowedPattern = RegExp(r'[^A-Za-z0-9\u4e00-\u9fff]');

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