import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_hbb/models/platform_model.dart';

/// 应用认证服务 - 处理用户注册、登录、短信验证码等
class AppAuthService {
  static const String _serverBaseUrl = 'https://112.74.59.152';
  static const String _tokenKey = 'app_user_token';
  static const String _userInfoKey = 'app_user_info';
  static const String _tokenVersionKey = 'app_user_token_version';
  static const String _securePrefix = 'enc:v1:';
  static const String _secureSalt = 'gamwing-app-auth-v1';

  static final AppAuthService _instance = AppAuthService._();
  factory AppAuthService() => _instance;
  AppAuthService._();

  encrypt_lib.Key? _cachedKey;
  encrypt_lib.IV? _cachedIv;
  bool _storageMigrated = false;

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    await _ensureSecureStorageMigrated();
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

  /// 保存登录信息
  Future<void> _saveLoginInfo(String token, Map<String, dynamic> user) async {
    await _setSecureLocalOption(_tokenKey, token);
    await _setSecureLocalOption(_userInfoKey, jsonEncode(user));
  }

  /// 退出登录
  Future<void> logout() async {
    await _setSecureLocalOption(_tokenKey, '');
    await _setSecureLocalOption(_userInfoKey, '');
    await _setSecureLocalOption(_tokenVersionKey, '');
  }

  /// 用户注册
  /// 返回 null 表示成功，返回错误信息表示失败
  Future<String?> register({
    required String username,
    required String password,
    required String phone,
    required String smsCode,
    required String activationCode,
  }) async {
    try {
      final result = await _post('/api/user/register', {
        'username': username,
        'password': password,
        'phone': phone,
        'sms_code': smsCode,
        'activation_code': activationCode,
      });
      if (result['code'] == 200) {
        return null; // 成功
      }
      return result['msg'] ?? '注册失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    try {
      final result = await _post('/api/user/login', {
        'username': username,
        'password': password,
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
      return result['msg'] ?? '登录失败';
    } catch (e) {
      return '网络错误: $e';
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
      return result['msg'] ?? '发送失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// 手机号+验证码登录
  Future<String?> smsLogin({
    required String phone,
    required String code,
  }) async {
    try {
      final result = await _post('/api/user/sms/login', {
        'phone': phone,
        'code': code,
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
      return result['msg'] ?? '登录失败';
    } catch (e) {
      return '网络错误: $e';
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
      return result['msg'] ?? '重置失败';
    } catch (e) {
      return '网络错误: $e';
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
      request.headers.set('Content-Type', 'application/json');
      try {
        final deviceId = await bind.mainGetMyId();
        if (deviceId.isNotEmpty) {
          request.headers.set('X-Device-Id', deviceId);
        }
      } catch (_) {}
      request.write(jsonEncode(body));
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
