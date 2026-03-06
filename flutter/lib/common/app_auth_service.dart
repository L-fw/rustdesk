import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/platform_model.dart';

/// 应用认证服务 - 处理用户注册、登录、短信验证码等
class AppAuthService {
  static const String _serverBaseUrl = 'http://112.74.59.152:3000';
  static const String _tokenKey = 'app_user_token';
  static const String _userInfoKey = 'app_user_info';
  static const String _tokenVersionKey = 'app_user_token_version';

  static final AppAuthService _instance = AppAuthService._();
  factory AppAuthService() => _instance;
  AppAuthService._();

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final token = await bind.mainGetLocalOption(key: _tokenKey);
    if (token.isEmpty) return false;
    final ok = await _verifyToken(token);
    if (!ok) {
      await logout();
    }
    return ok;
  }

  /// 获取已保存的 token
  Future<String> getToken() async {
    return await bind.mainGetLocalOption(key: _tokenKey);
  }

  /// 保存登录信息
  Future<void> _saveLoginInfo(String token, Map<String, dynamic> user) async {
    await bind.mainSetLocalOption(key: _tokenKey, value: token);
    await bind.mainSetLocalOption(key: _userInfoKey, value: jsonEncode(user));
  }

  /// 退出登录
  Future<void> logout() async {
    await bind.mainSetLocalOption(key: _tokenKey, value: '');
    await bind.mainSetLocalOption(key: _userInfoKey, value: '');
    await bind.mainSetLocalOption(key: _tokenVersionKey, value: '');
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
        await bind.mainSetLocalOption(
          key: _tokenVersionKey,
          value: '${result['token_version'] ?? ''}',
        );
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
        await bind.mainSetLocalOption(
          key: _tokenVersionKey,
          value: '${result['token_version'] ?? ''}',
        );
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
      final tokenVersion =
          await bind.mainGetLocalOption(key: _tokenVersionKey);
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
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request =
          await client.postUrl(Uri.parse('$_serverBaseUrl$path'));
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
}
