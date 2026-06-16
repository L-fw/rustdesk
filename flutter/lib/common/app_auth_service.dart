import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

import '../common.dart';

/// 应用认证服务 - 处理用户注册、登录、短信验证码等
class AppAuthService {
  static const String _serverBaseUrl = 'https://jyyxt.cloud';
  static const String _tokenKey = 'app_user_token';
  static const String _userInfoKey = 'app_user_info';
  static const String _tokenVersionKey = 'app_user_token_version';
  static const String _rememberPasswordKey = 'app_login_remember_password_map';
  static const String _securePrefix = 'enc:v1:';
  static const String _secureSalt = 'gamwing-app-auth-v1';

  static final AppAuthService _instance = AppAuthService._();
  factory AppAuthService() => _instance;
  AppAuthService._();

  encrypt_lib.Key? _cachedKey;
  encrypt_lib.IV? _cachedIv;
  bool _storageMigrated = false;
  final RxString currentUserName = ''.obs;

  /// 已知服务器返回的中文消息 → i18n key 映射
  static const Map<String, String> _serverMsgMap = {
    '用户名或密码错误': 'server_wrong_credentials',
    '密码错误': 'server_wrong_password',
    '用户不存在': 'server_user_not_found',
    '用户名已存在': 'server_username_exists',
    '手机号已注册': 'server_phone_registered',
    '验证码错误': 'server_wrong_sms_code',
    '验证码已过期': 'server_sms_code_expired',
    '验证码发送过于频繁': 'server_sms_too_frequent',
    '激活码无效': 'server_invalid_activation_code',
    '激活码已过期': 'activation_code_expired_error',
    '激活码已被使用': 'server_activation_code_used',
    '激活码已被禁用': 'server_activation_code_disabled',
    '账号已被禁用': 'server_account_disabled',
    '手机号格式错误': 'server_invalid_phone_format',
    '参数错误': 'server_invalid_params',
    '服务器内部错误': 'server_internal_error',
    '请求过于频繁，请稍后再试': 'server_rate_limited',
    '手机号与当前账号不匹配': 'deregister_phone_mismatch',
    '新用户名不能与当前用户名相同': 'username_unchanged',
    '用户名需为 1-20 位字符，只能包含中文、英文和数字': 'username_rule_tip',
  };

  /// 尝试将服务器返回的消息翻译为当前语言
  /// 如果是已知的中文消息，返回翻译后的文本；否则原样返回
  String? _translateServerMsg(dynamic msg) {
    if (msg == null) return null;
    final text = msg.toString().trim();
    if (text.isEmpty) return null;
    final key = _serverMsgMap[text];
    if (key != null) return translate(key);
    return text; // 未知消息原样返回
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    await _ensureSecureStorageMigrated();
    await _loadCachedUserInfo();
    final token = await _getSecureLocalOption(_tokenKey);
    if (token.isEmpty) return false;
    final ok = await _verifyToken(token);
    if (!ok) {
      await logout();
    }
    return ok;
  }

  /// 获取已保存的 token
  Future<String> getToken() async {
    await _ensureSecureStorageMigrated();
    return await _getSecureLocalOption(_tokenKey);
  }

  /// 获取已保存的用户信息
  Future<Map<String, dynamic>?> getUserInfo() async {
    await _ensureSecureStorageMigrated();
    final raw = await _getSecureLocalOption(_userInfoKey);
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// 保存登录信息
  Future<void> _saveLoginInfo(String token, Map<String, dynamic> user) async {
    await _setSecureLocalOption(_tokenKey, token);
    await _setSecureLocalOption(_userInfoKey, jsonEncode(user));
    final userName = _extractUserName(user);
    currentUserName.value = userName;
    // Set plain-text user name for Rust-side peers directory isolation
    await bind.mainSetLocalOption(key: 'current_user_name', value: userName);
    bind.mainLoadRecentPeers();
    stateGlobal.appLoginInvalidated.value = false;
    stateGlobal.appLoginInvalidatedMessage.value = '';
  }

  /// 退出登录
  Future<void> logout() async {
    await _setSecureLocalOption(_tokenKey, '');
    await _setSecureLocalOption(_userInfoKey, '');
    await _setSecureLocalOption(_tokenVersionKey, '');
    currentUserName.value = '';
    // Clear user name so Rust uses the default 'peers' directory
    await bind.mainSetLocalOption(key: 'current_user_name', value: '');
    bind.mainLoadRecentPeers();
    if (stateGlobal.appLoginInvalidated.isFalse) {
      stateGlobal.appLoginInvalidatedMessage.value = '';
    }
  }

  Future<void> _loadCachedUserInfo() async {
    final raw = await _getSecureLocalOption(_userInfoKey);
    if (raw.isEmpty) {
      if (currentUserName.value.isNotEmpty) {
        currentUserName.value = '';
      }
      // Ensure Rust side also uses default peers directory
      await bind.mainSetLocalOption(key: 'current_user_name', value: '');
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final name = _extractUserName(decoded);
        currentUserName.value = name;
        // Sync to Rust side for peers directory isolation on app startup
        await bind.mainSetLocalOption(key: 'current_user_name', value: name);
      }
    } catch (_) {
      currentUserName.value = '';
      await bind.mainSetLocalOption(key: 'current_user_name', value: '');
    }
  }

  String _extractUserName(Map<String, dynamic> user) {
    for (final value in [
      user['display_name'],
      user['name'],
      user['username'],
      user['phone'],
    ]) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Future<void> saveRememberedPassword({
    required String username,
    required String password,
    required DateTime expiresAt,
  }) async {
    if (username.isEmpty || password.isEmpty) return;
    final data = await _getRememberedPasswordMap();
    data[username] = {
      'password': password,
      'expires_at': expiresAt.toIso8601String(),
    };
    await _setSecureLocalOption(_rememberPasswordKey, jsonEncode(data));
  }

  Future<String?> getRememberedPassword(String username) async {
    if (username.isEmpty) return null;
    final data = await _getRememberedPasswordMap();
    final entry = data[username];
    if (entry is Map) {
      final rawExpire = entry['expires_at']?.toString() ?? '';
      if (rawExpire.isNotEmpty) {
        final expire = DateTime.tryParse(rawExpire);
        if (expire != null && DateTime.now().isAfter(expire)) {
          data.remove(username);
          await _setSecureLocalOption(_rememberPasswordKey, jsonEncode(data));
          return null;
        }
      }
      final pwd = entry['password']?.toString() ?? '';
      return pwd.isEmpty ? null : pwd;
    }
    return null;
  }

  Future<void> clearRememberedPassword(String username) async {
    if (username.isEmpty) return;
    final data = await _getRememberedPasswordMap();
    if (data.remove(username) != null) {
      await _setSecureLocalOption(_rememberPasswordKey, jsonEncode(data));
    }
  }

  Future<Map<String, dynamic>> _getRememberedPasswordMap() async {
    await _ensureSecureStorageMigrated();
    final raw = await _getSecureLocalOption(_rememberPasswordKey);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return {};
  }

  /// 用户注册
  /// 返回 null 表示成功，返回错误信息表示失败
  Future<String?> register({
    required String username,
    required String password,
    required String phone,
    required String smsCode,
    required String activationCode,
    String? agreedTermsVersion,
    String? agreedPrivacyVersion,
    String? agreedTime,
  }) async {
    try {
      final result = await _post('/api/user/register', {
        'username': username,
        'password': password,
        'phone': phone,
        'sms_code': smsCode,
        'activation_code': activationCode,
        if (agreedTermsVersion != null) 'agreed_terms_version': agreedTermsVersion,
        if (agreedPrivacyVersion != null) 'agreed_privacy_version': agreedPrivacyVersion,
        if (agreedTime != null) 'agreed_time': agreedTime,
      });
      if (result['code'] == 200) {
        return null; // 成功
      }
      return _translateServerMsg(result['msg']) ?? translate('register_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  Future<String?> login({
    required String username,
    required String password,
    String? activationCode,
    String? agreedTermsVersion,
    String? agreedPrivacyVersion,
    String? agreedTime,
  }) async {
    try {
      final result = await _post('/api/user/login', {
        'username': username,
        'password': password,
        if (activationCode != null) 'activation_code': activationCode,
        if (agreedTermsVersion != null) 'agreed_terms_version': agreedTermsVersion,
        if (agreedPrivacyVersion != null) 'agreed_privacy_version': agreedPrivacyVersion,
        if (agreedTime != null) 'agreed_time': agreedTime,
      });
      if (result['code'] == 200 && result['token'] != null) {
        await _saveLoginInfo(
          result['token'],
          result['user'] ?? {},
        );
        await _setSecureLocalOption(
            _tokenVersionKey, '${result['token_version'] ?? ''}');
        return null; // 成功
      }
      return _translateServerMsg(result['msg']) ?? translate('login_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 发送短信验证码
  Future<String?> sendSmsCode({required String phone}) async {
    try {
      final result = await _post('/api/user/sms/send', {
        'phone': phone,
      });
      if (result['code'] == 200) {
        return null;
      }
      return _translateServerMsg(result['msg']) ?? translate('send_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 手机号+验证码登录
  Future<String?> smsLogin({
    required String phone,
    required String code,
    String? activationCode,
    String? agreedTermsVersion,
    String? agreedPrivacyVersion,
    String? agreedTime,
  }) async {
    try {
      final result = await _post('/api/user/sms/login', {
        'phone': phone,
        'code': code,
        if (activationCode != null) 'activation_code': activationCode,
        if (agreedTermsVersion != null) 'agreed_terms_version': agreedTermsVersion,
        if (agreedPrivacyVersion != null) 'agreed_privacy_version': agreedPrivacyVersion,
        if (agreedTime != null) 'agreed_time': agreedTime,
      });
      if (result['code'] == 200 && result['token'] != null) {
        await _saveLoginInfo(
          result['token'],
          result['user'] ?? {},
        );
        await _setSecureLocalOption(
            _tokenVersionKey, '${result['token_version'] ?? ''}');
        return null;
      }
      return _translateServerMsg(result['msg']) ?? translate('login_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  Future<String?> resetPassword({
    required String phone,
    required String smsCode,
    required String newPassword,
  }) async {
    try {
      final result = await _post('/api/user/password/reset', {
        'phone': phone,
        'sms_code': smsCode,
        'new_password': newPassword,
      });
      if (result['code'] == 200) {
        await logout();
        return null;
      }
      return _translateServerMsg(result['msg']) ?? translate('reset_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 修改密码：凭旧密码验证当前登录账号后设置新密码
  /// 返回 null 表示成功，返回错误信息表示失败
  Future<String?> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final token = await getToken();
      if (token.isEmpty) return translate('login_failed');
      final result = await _post('/api/user/password/change', {
        'token': token,
        'old_password': oldPassword,
        'new_password': newPassword,
      });
      if (result['code'] == 200) {
        await logout();
        return null; // 成功
      }
      return _translateServerMsg(result['msg']) ?? translate('change_pwd_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 修改用户名：凭登录密码验证身份后，将当前账号的用户名改为新用户名。
  /// 成功后会同步更新本地缓存的用户信息与 current_user_name（用于本地"最近连接"
  /// 目录隔离），token 保持不变，无需重新登录。
  /// 返回 null 表示成功，返回错误信息表示失败。
  Future<String?> changeUsername({
    required String newUsername,
    required String password,
  }) async {
    try {
      final token = await getToken();
      if (token.isEmpty) return translate('login_failed');
      final result = await _post('/api/user/username/change', {
        'token': token,
        'password': password,
        'new_username': newUsername,
      });
      if (result['code'] == 200) {
        final serverUser = result['user'];
        final resolvedName = (serverUser is Map && serverUser['username'] != null)
            ? serverUser['username'].toString()
            : newUsername;
        // 更新本地缓存的用户信息，使设置页与各处显示同步刷新
        final info = await getUserInfo() ?? <String, dynamic>{};
        info['username'] = resolvedName;
        await _setSecureLocalOption(_userInfoKey, jsonEncode(info));
        // 同步用户名到 Rust 侧：会触发本地 peers 目录迁移并保持隔离一致
        final displayName = _extractUserName(Map<String, dynamic>.from(info));
        currentUserName.value = displayName;
        await bind.mainSetLocalOption(
            key: 'current_user_name', value: displayName);
        bind.mainLoadRecentPeers();
        return null; // 成功
      }
      return _translateServerMsg(result['msg']) ??
          translate('change_username_failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 注销账号：手机号 + 验证码验证后永久删除当前登录账号
  /// 返回 null 表示成功，返回错误信息表示失败
  Future<String?> deleteAccount({
    required String phone,
    required String smsCode,
  }) async {
    try {
      final token = await getToken();
      if (token.isEmpty) return translate('login_failed');
      final result = await _post('/api/user/account/delete', {
        'token': token,
        'phone': phone,
        'sms_code': smsCode,
      });
      if (result['code'] == 200) {
        await logout();
        return null; // 成功
      }
      return _translateServerMsg(result['msg']) ?? translate('Failed');
    } catch (e) {
      return '${translate('network_error')}: $e';
    }
  }

  /// 获取当前登录用户的设备列表（"我的设备"）
  /// 返回 null 表示请求失败（网络异常 / 未登录 / token 失效）
  Future<List<Map<String, dynamic>>?> fetchMyDevices() async {
    try {
      final token = await getToken();
      if (token.isEmpty) return null;
      final result = await _post('/api/user/devices', {'token': token});
      if (result['code'] == 200 && result['data'] is List) {
        return (result['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      if (result['code'] == 401) {
        // token 已失效，清理本地登录态
        await logout();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取当前登录用户的最近连接记录（会话历史）
  /// 返回 null 表示请求失败（网络异常 / 未登录 / token 失效）
  Future<List<Map<String, dynamic>>?> fetchMySessions() async {
    try {
      final token = await getToken();
      if (token.isEmpty) return null;
      final result = await _post('/api/user/sessions', {'token': token});
      if (result['code'] == 200 && result['data'] is List) {
        return (result['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      if (result['code'] == 401) await logout();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 清空当前登录用户的会话记录。成功返回 true。
  Future<bool> clearMySessions() async {
    try {
      final token = await getToken();
      if (token.isEmpty) return false;
      final result = await _post('/api/user/sessions/clear', {'token': token});
      return result['code'] == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取当前登录用户的收藏列表
  Future<List<Map<String, dynamic>>?> fetchMyFavorites() async {
    try {
      final token = await getToken();
      if (token.isEmpty) return null;
      final result = await _post('/api/user/favorites', {'token': token});
      if (result['code'] == 200 && result['data'] is List) {
        return (result['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      if (result['code'] == 401) await logout();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 批量查询给定 peer id 当前是否在线。判断逻辑与收藏一致（服务器端基于
  /// WebSocket 在连状态 wsClients）。返回在线的 id 集合；请求失败返回 null。
  Future<Set<String>?> fetchPeersOnline(List<String> peerIds) async {
    try {
      if (peerIds.isEmpty) return <String>{};
      final token = await getToken();
      if (token.isEmpty) return null;
      final result = await _post('/api/user/peers/online', {
        'token': token,
        'peer_ids': peerIds,
      });
      if (result['code'] == 200 && result['data'] is Map) {
        final online = (result['data']['online'] as List?) ?? const [];
        return online.map((e) => e.toString()).toSet();
      }
      if (result['code'] == 401) await logout();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 添加收藏。成功返回 true。
  Future<bool> addFavorite(String peerId, {String? alias}) async {
    try {
      final token = await getToken();
      if (token.isEmpty || peerId.isEmpty) return false;
      final result = await _post('/api/user/favorites/add', {
        'token': token,
        'peer_id': peerId,
        if (alias != null) 'alias': alias,
      });
      return result['code'] == 200;
    } catch (_) {
      return false;
    }
  }

  /// 取消收藏。成功返回 true。
  Future<bool> removeFavorite(String peerId) async {
    try {
      final token = await getToken();
      if (token.isEmpty || peerId.isEmpty) return false;
      final result = await _post('/api/user/favorites/remove', {
        'token': token,
        'peer_id': peerId,
      });
      return result['code'] == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyToken(String token) async {
    try {
      final tokenVersion = await _getSecureLocalOption(_tokenVersionKey);
      final result = await _post('/api/user/token/verify', {
        'token': token,
        'token_version': tokenVersion,
      });
      if (result['code'] == 200) return true;
      if (result['code'] == 401) return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  /// 通用 POST 请求
  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final serverUri = Uri.parse(_serverBaseUrl);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.badCertificateCallback =
        (X509Certificate _, String host, int __) => host == serverUri.host;
    try {
      final request = await client.postUrl(serverUri.resolve(path));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      try {
        final deviceId = await bind.mainGetMyId();
        if (deviceId.isNotEmpty) {
          request.headers.set('X-Device-Id', deviceId);
        }
      } catch (_) {}
      // 声明本端类型，避免服务器在登录绑定时把桌面端误标为移动端
      request.headers.set('X-Client-Type', isDesktop ? 'desktop' : kAppMode);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _ensureSecureStorageMigrated() async {
    if (_storageMigrated) {
      return;
    }
    _storageMigrated = true;
    await _migrateLegacyKey(_tokenKey);
    await _migrateLegacyKey(_userInfoKey);
    await _migrateLegacyKey(_tokenVersionKey);
  }

  Future<void> _migrateLegacyKey(String key) async {
    try {
      final raw = await bind.mainGetLocalOption(key: key);
      if (raw.isEmpty || raw.startsWith(_securePrefix)) {
        return;
      }
      await _setSecureLocalOption(key, raw);
    } catch (_) {}
  }

  Future<void> _setSecureLocalOption(String key, String value) async {
    if (value.isEmpty) {
      await bind.mainSetLocalOption(key: key, value: '');
      return;
    }
    final encrypted = await _encryptLocalValue(value);
    await bind.mainSetLocalOption(key: key, value: encrypted);
  }

  Future<String> _getSecureLocalOption(String key) async {
    final raw = await bind.mainGetLocalOption(key: key);
    return _decryptLocalValue(raw);
  }

  Future<String> _encryptLocalValue(String value) async {
    final encrypter = await _getEncrypter();
    final iv = await _getIv();
    final encrypted = encrypter.encrypt(value, iv: iv).base64;
    return '$_securePrefix$encrypted';
  }

  Future<String> _decryptLocalValue(String value) async {
    if (value.isEmpty) {
      return '';
    }
    if (!value.startsWith(_securePrefix)) {
      return value;
    }
    try {
      final payload = value.substring(_securePrefix.length);
      final encrypter = await _getEncrypter();
      final iv = await _getIv();
      return encrypter.decrypt64(payload, iv: iv);
    } catch (_) {
      return '';
    }
  }

  Future<encrypt_lib.Encrypter> _getEncrypter() async {
    final key = await _getKey();
    return encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc));
  }

  Future<encrypt_lib.Key> _getKey() async {
    if (_cachedKey != null) {
      return _cachedKey!;
    }
    final deviceId = await _getDeviceIdSeed();
    final seed = '$deviceId|$_secureSalt';
    final keyText = seed.padRight(32, '0').substring(0, 32);
    _cachedKey = encrypt_lib.Key.fromUtf8(keyText);
    return _cachedKey!;
  }

  Future<encrypt_lib.IV> _getIv() async {
    if (_cachedIv != null) {
      return _cachedIv!;
    }
    final deviceId = await _getDeviceIdSeed();
    final reversedId = deviceId.split('').reversed.join();
    final seed = '$_secureSalt|$reversedId';
    final ivText = seed.padRight(16, '0').substring(0, 16);
    _cachedIv = encrypt_lib.IV.fromUtf8(ivText);
    return _cachedIv!;
  }

  Future<String> _getDeviceIdSeed() async {
    try {
      final id = await bind.mainGetMyId();
      if (id.isNotEmpty) {
        return id;
      }
    } catch (_) {}
    return 'unknown-device';
  }
}
