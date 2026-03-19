// ═══════════════════════════════════════════════════════
// Gamwing 设备管理后台 + 版本检查 API
// 端口：3000
// ═══════════════════════════════════════════════════════

const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const crypto = require('crypto');
const bcrypt = require('bcrypt');

const {
  initSQLiteDatabase,
  dbGetUser, dbGetUserByPhone, dbGetUserByToken, dbSaveUser, dbDeleteUser, dbListUsers,
  dbGetDevice, dbGetAllDevices, dbUpsertDevice, dbGetDevicesByUser, dbSetDeviceBanned, dbDeleteDevice,
  dbAddSession, dbUpdateSessionHeartbeat, dbEndSession, dbGetDeviceSessions,
  dbGetActivationCode, dbGetAllActivationCodes, dbSaveActivationCode, dbDeleteActivationCode,
} = require('./sqlite_db');

const app = express();
app.use(express.json());

// ───────────────────────────────────────────────────────
// WebSocket 连接管理
// key = deviceId, value = Set<WebSocket>
// ───────────────────────────────────────────────────────
const wsClients = new Map();

// ───────────────────────────────────────────────────────
// 配置
// ───────────────────────────────────────────────────────
const ADMIN_RAW_PASSWORD = process.env.ADMIN_PASSWORD ?? '    ';
const ADMIN_PASSWORD_HASH = crypto.createHash('sha256').update(ADMIN_RAW_PASSWORD).digest('hex');
console.log(`[AUTH] Admin password hash: ${ADMIN_PASSWORD_HASH.substring(0, 16)}...`);

// ───────────────────────────────────────────────────────
// AES 加解密工具（用于设备密码传输加密）
// ───────────────────────────────────────────────────────
const AES_KEY = Buffer.from('gamwing-rustdesk-2024-secret-k!!'); // 32 bytes
const AES_IV = Buffer.from('0123456789abcdef');                 // 16 bytes

function decryptPassword(encrypted) {
  try {
    const decipher = crypto.createDecipheriv('aes-256-cbc', AES_KEY, AES_IV);
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  } catch {
    return encrypted; // 兼容旧版未加密客户端
  }
}

const SESSION_TOKEN = 'rustdesk-admin-session-' + Date.now();
const TOKEN_VERSION_MAX = 1000000;

const VERSION_FILE = path.join(__dirname, 'version.json');
const LEGACY_ACTIVATION_CODES_FILE = path.join(__dirname, 'version-check', 'activation_codes.json');

const APK_ROOT_RELATIVE_PATH = './apk';
const APK_FULL_RELATIVE_PATH = './apk/full';
const APK_SHARE_ONLY_RELATIVE_PATH = './apk/share_only';
const APK_DESKTOP_RELATIVE_PATH = './apk/desktop';
const APK_ROOT_DIR = path.join(__dirname, APK_ROOT_RELATIVE_PATH);
const APK_DIR_FULL = path.join(__dirname, APK_FULL_RELATIVE_PATH);
const APK_DIR_SHARE_ONLY = path.join(__dirname, APK_SHARE_ONLY_RELATIVE_PATH);
const APK_DIR_DESKTOP = path.join(__dirname, APK_DESKTOP_RELATIVE_PATH);

// 心跳超时：超过此时间没有心跳视为会话已断开（毫秒）
const SESSION_TIMEOUT_MS = 90 * 1000; // 90秒

// 确保 APK 目录存在
[APK_ROOT_DIR, APK_DIR_FULL, APK_DIR_SHARE_ONLY, APK_DIR_DESKTOP].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

// ───────────────────────────────────────────────────────
// 版本配置管理（持久化到 version.json）
// ───────────────────────────────────────────────────────
const DEFAULT_VERSION_CONFIG = {
  android: {
    full: {
      latestVersion: '1.8.0',
      latestTermsVersion: '1.0',
      latestPrivacyVersion: '1.0',
      minRequired: '1.4.5',
      forceUpdate: false,
      downloadUrl: '/download/full/rustdesk-latest.apk',
      updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
      releaseUrl: 'http://112.74.59.152/releases/tag/1.8.0',
    },
    share_only: {
      latestVersion: '1.8.0',
      latestTermsVersion: '1.0',
      latestPrivacyVersion: '1.0',
      minRequired: '1.4.5',
      forceUpdate: false,
      downloadUrl: '/download/share_only/rustdesk-latest.apk',
      updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
      releaseUrl: 'http://112.74.59.152/releases/tag/1.8.0',
    },
    desktop: {
      latestVersion: '1.8.0',
      latestTermsVersion: '1.0',
      latestPrivacyVersion: '1.0',
      minRequired: '1.4.5',
      forceUpdate: false,
      downloadUrl: '/download/desktop/rustdesk-latest.apk',
      updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
      releaseUrl: 'http://112.74.59.152/releases/tag/1.8.0',
    },
  },
};

const VERSION_CLIENT_TYPES = new Set(['full', 'share_only', 'desktop']);
const VERSION_CONFIG_FIELDS = [
  'latestVersion', 'latestTermsVersion', 'latestPrivacyVersion',
  'minRequired', 'forceUpdate', 'downloadUrl', 'updateLog', 'releaseUrl',
];

function cloneDefaultVersionConfig() {
  return JSON.parse(JSON.stringify(DEFAULT_VERSION_CONFIG));
}

function normalizeVersionClientType(clientType) {
  return VERSION_CLIENT_TYPES.has(clientType) ? clientType : 'full';
}

function getVersionClientTypeFromReq(req) {
  return normalizeVersionClientType(
    req.query.client_type || req.body?.clientType || req.body?.client_type);
}

function getApkDirByClientType(clientType) {
  if (clientType === 'share_only') return APK_DIR_SHARE_ONLY;
  if (clientType === 'desktop') return APK_DIR_DESKTOP;
  return APK_DIR_FULL;
}

function mergeVersionFields(target, source) {
  if (!source || typeof source !== 'object') return;
  for (const key of VERSION_CONFIG_FIELDS) {
    if (source[key] !== undefined) {
      target[key] = key === 'forceUpdate' ? !!source[key] : source[key];
    }
  }
}

function parseVersionSegments(version) {
  if (typeof version !== 'string') return [];
  const matches = version.match(/\d+/g);
  if (!matches) return [];
  return matches.map(s => parseInt(s, 10)).filter(Number.isFinite);
}

function normalizeUsername(value) {
  if (value === undefined || value === null) return '';
  return String(value).trim().normalize('NFKC');
}

function isValidUsername(value) {
  if (!value) return false;
  return /^[A-Za-z0-9\u4e00-\u9fff]+$/.test(value);
}

function compareVersion(versionA, versionB) {
  const left = parseVersionSegments(versionA);
  const right = parseVersionSegments(versionB);
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) {
    const a = left[i] ?? 0;
    const b = right[i] ?? 0;
    if (a < b) return -1;
    if (a > b) return 1;
  }
  return 0;
}

function normalizeVersionConfig(rawConfig) {
  const normalized = cloneDefaultVersionConfig();
  if (!rawConfig || typeof rawConfig !== 'object') return normalized;
  const android = rawConfig.android;
  if (!android || typeof android !== 'object') return normalized;
  if (android.full || android.share_only || android.desktop) {
    mergeVersionFields(normalized.android.full, android.full);
    mergeVersionFields(normalized.android.share_only, android.share_only);
    mergeVersionFields(normalized.android.desktop, android.desktop);
    return normalized;
  }
  mergeVersionFields(normalized.android.full, android);
  mergeVersionFields(normalized.android.share_only, android);
  mergeVersionFields(normalized.android.desktop, android);
  return normalized;
}

function loadVersionConfig() {
  if (!fs.existsSync(VERSION_FILE)) {
    saveVersionConfig(DEFAULT_VERSION_CONFIG);
    return cloneDefaultVersionConfig();
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8'));
    const normalized = normalizeVersionConfig(parsed);
    if (JSON.stringify(parsed) !== JSON.stringify(normalized)) saveVersionConfig(normalized);
    return normalized;
  } catch { return cloneDefaultVersionConfig(); }
}

function saveVersionConfig(config) {
  fs.writeFileSync(VERSION_FILE, JSON.stringify(config, null, 2));
}

// multer 配置：APK 上传
const apkStorage = multer.diskStorage({
  destination: (req, _file, cb) =>
    cb(null, getApkDirByClientType(getVersionClientTypeFromReq(req))),
  filename: (_req, file, cb) => cb(null, file.originalname),
});
const uploadApk = multer({
  storage: apkStorage,
  limits: { fileSize: 200 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const clientType = getVersionClientTypeFromReq(req);
    const name = file.originalname.toLowerCase();
    if (clientType === 'desktop') {
      if (name.endsWith('.exe')) cb(null, true);
      else cb(new Error('桌面版只允许上传 .exe 文件'));
    } else {
      if (name.endsWith('.apk')) cb(null, true);
      else cb(new Error('只允许上传 .apk 文件'));
    }
  },
});

// 静态文件服务：提供 APK 下载
app.use('/download/full', express.static(APK_DIR_FULL));
app.use('/download/share_only', express.static(APK_DIR_SHARE_ONLY));
app.use('/download/desktop', express.static(APK_DIR_DESKTOP));
app.use('/download', express.static(APK_DIR_FULL));

// ───────────────────────────────────────────────────────
// 会话状态辅助函数（操作 session 行数组）
// ───────────────────────────────────────────────────────
function isRemoting(sessions) {
  if (!sessions?.length) return false;
  const now = Date.now();
  return sessions.some(s => {
    if (s.ended) return false;
    return now - new Date(s.last_heartbeat || s.start_time).getTime() < SESSION_TIMEOUT_MS;
  });
}

function getActiveSessions(sessions) {
  if (!sessions?.length) return [];
  const now = Date.now();
  return sessions.filter(s => {
    if (s.ended) return false;
    return now - new Date(s.last_heartbeat || s.start_time).getTime() < SESSION_TIMEOUT_MS;
  });
}

// ───────────────────────────────────────────────────────
// API 响应字段映射：snake_case（DB）→ camelCase（前端）
// admin.html 全部使用 camelCase，这里统一转换
// ───────────────────────────────────────────────────────
function mapSession(s) {
  if (!s) return s;
  return {
    id: s.id,
    deviceId: s.device_id,
    sessionId: s.session_id,
    peerId: s.peer_id || null,
    username: s.username || null,
    phone: s.phone || null,
    startTime: s.start_time || null,
    lastHeartbeat: s.last_heartbeat || null,
    ended: !!s.ended,
    endTime: s.end_time || null,
  };
}

function mapDevice(d, sessions = []) {
  const mappedSessions = sessions.map(mapSession);
  return {
    id: d.id,
    ip: d.ip || null,
    username: d.username || null,
    phone: d.phone || null,
    appVersion: d.app_version || null,
    password: d.password || null,
    clientType: d.client_type || d.clientType || null,
    permissions: d.permissions || {},
    banned: !!d.banned,
    firstSeen: d.first_seen || null,
    lastSeen: d.last_seen || null,
    remoting: isRemoting(sessions),        // 用原始 snake_case 行计算
    activeSessions: getActiveSessions(sessions).map(mapSession),
    sessions: mappedSessions,
  };
}

// ───────────────────────────────────────────────────────
// 管理员认证中间件
// ───────────────────────────────────────────────────────
function authMiddleware(req, res, next) {
  const token = req.headers['x-admin-token'];
  if (token !== SESSION_TOKEN) return res.status(401).json({ code: 401, msg: '未授权' });
  next();
}

// ───────────────────────────────────────────────────────
// 激活码工具函数
// ───────────────────────────────────────────────────────
function normalizeActivationCode(code) {
  return String(code || '').trim().replace(/[\s-]/g, '').toUpperCase();
}

function hashActivationCode(normalizedCode) {
  return crypto.createHash('sha256').update(normalizedCode).digest('hex');
}

function generateActivationCode({ length = 16, group = 4 } = {}) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(length);
  let raw = '';
  for (let i = 0; i < length; i++) raw += alphabet[bytes[i] % alphabet.length];
  if (!group || group <= 0) return raw;
  const parts = [];
  for (let i = 0; i < raw.length; i += group) parts.push(raw.slice(i, i + group));
  return parts.join('-');
}

async function applyActivationCodeForUser({ activationCode, username, phone, req }) {
  const normalizedCode = normalizeActivationCode(activationCode);
  if (!normalizedCode) return { ok: false, msg: '激活码不能为空' };
  const codeHash = hashActivationCode(normalizedCode);
  const entry = await dbGetActivationCode(codeHash);
  if (!entry) return { ok: false, msg: '激活码无效' };
  if (entry.revoked) return { ok: false, msg: '激活码已被禁用' };
  const expiresMs = entry.expires_at ? Date.parse(entry.expires_at) : NaN;
  if (!Number.isNaN(expiresMs) && Date.now() > expiresMs)
    return { ok: false, msg: '激活码已过期' };
  const maxUses = Number.isFinite(entry.max_uses) ? entry.max_uses : 1;
  const usedCount = Number.isFinite(entry.used_count) ? entry.used_count : 0;
  if (usedCount >= maxUses) return { ok: false, msg: '激活码已被使用' };
  const usedRecords = Array.isArray(entry.used_records) ? entry.used_records : [];
  const lastUsedAt = new Date().toISOString();
  usedRecords.push({
    username,
    phone: phone || '',
    ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
    at: lastUsedAt,
  });
  await dbSaveActivationCode({
    ...entry,
    used_count: usedCount + 1,
    last_used_at: lastUsedAt,
    used_records: usedRecords,
  });
  return { ok: true, codeHash };
}

// 短信验证码内存存储: { phone: { code, expireAt } }
const smsCodeStore = new Map();
const SMS_CODE_EXPIRE_MS = 5 * 60 * 1000; // 5 分钟

function generateUserToken() {
  return crypto.randomBytes(32).toString('hex');
}

// ───────────────────────────────────────────────────────
// 用户注册接口
// POST /api/user/register
// ───────────────────────────────────────────────────────
app.post('/api/user/register', async (req, res) => {
  try {
    const {
      username, password, phone, sms_code, activation_code,
      agreed_terms_version, agreed_privacy_version, agreed_time,
    } = req.body || {};

    const versionConfig = loadVersionConfig();
    const latestTermsVersion = versionConfig.android?.full?.latestTermsVersion || '1.0';
    const latestPrivacyVersion = versionConfig.android?.full?.latestPrivacyVersion || '1.0';

    if (
      !agreed_terms_version || compareVersion(agreed_terms_version, latestTermsVersion) < 0 ||
      !agreed_privacy_version || compareVersion(agreed_privacy_version, latestPrivacyVersion) < 0
    ) {
      return res.status(400).json({ code: 400, msg: '请先同意最新版本的用户协议与隐私政策' });
    }

    const normalizedUsername = normalizeUsername(username);
    if (!normalizedUsername || !password)
      return res.status(400).json({ code: 400, msg: '用户名和密码不能为空' });
    if (!isValidUsername(normalizedUsername))
      return res.status(400).json({ code: 400, msg: '用户名只能包含中文、英文和数字' });
    if (!phone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });
    if (!sms_code) return res.status(400).json({ code: 400, msg: '验证码不能为空' });
    if (!activation_code) return res.status(400).json({ code: 400, msg: '激活码不能为空' });

    const normalizedPhone = String(phone).trim();
    const normalizedSmsCode = String(sms_code).trim();
    if (!normalizedPhone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });
    if (!normalizedSmsCode) return res.status(400).json({ code: 400, msg: '验证码不能为空' });

    if (await dbGetUser(normalizedUsername))
      return res.status(400).json({ code: 400, msg: '用户名已存在' });
    if (await dbGetUserByPhone(normalizedPhone))
      return res.status(400).json({ code: 400, msg: '该手机号已被注册' });

    const storedSms = smsCodeStore.get(normalizedPhone);
    if (!storedSms || storedSms.code !== normalizedSmsCode)
      return res.status(401).json({ code: 401, msg: '验证码错误' });
    if (Date.now() > storedSms.expireAt) {
      smsCodeStore.delete(normalizedPhone);
      return res.status(401).json({ code: 401, msg: '验证码已过期' });
    }
    smsCodeStore.delete(normalizedPhone);

    const normalizedCode = normalizeActivationCode(activation_code);
    if (!normalizedCode) return res.status(400).json({ code: 400, msg: '激活码不能为空' });

    const codeHash = hashActivationCode(normalizedCode);
    const entry = await dbGetActivationCode(codeHash);
    if (!entry) return res.status(400).json({ code: 400, msg: '激活码无效' });
    if (entry.revoked) return res.status(400).json({ code: 400, msg: '激活码已被禁用' });

    const nowMs = Date.now();
    const expiresMs = entry.expires_at ? Date.parse(entry.expires_at) : NaN;
    if (!Number.isNaN(expiresMs) && nowMs > expiresMs)
      return res.status(400).json({ code: 400, msg: '激活码已过期' });

    const maxUses = Number.isFinite(entry.max_uses) ? entry.max_uses : 1;
    const usedCount = Number.isFinite(entry.used_count) ? entry.used_count : 0;
    if (usedCount >= maxUses) return res.status(400).json({ code: 400, msg: '激活码已被使用' });

    const passwordHash = await bcrypt.hash(password, 12);
    await dbSaveUser({
      username: normalizedUsername,
      password_hash: passwordHash,
      phone: normalizedPhone,
      activation_code_hash: codeHash,
      activated: true,
      created_at: new Date().toISOString(),
      token_version: 1,
      agreed_terms_version: agreed_terms_version || null,
      agreed_privacy_version: agreed_privacy_version || null,
      agreed_time: agreed_time || null,
    });

    const bindDeviceId = req.headers['x-device-id'];
    if (bindDeviceId) {
      const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
      await dbUpsertDevice(
        bindDeviceId,
        bindIp,
        null,
        null,
        null,
        normalizedUsername,
        normalizedPhone,
        'full');
    }

    // 更新激活码使用次数
    const usedRecords = Array.isArray(entry.used_records) ? entry.used_records : [];
    const lastUsedAt = new Date().toISOString();
    usedRecords.push({
      username: normalizedUsername,
      phone: phone || '',
      ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
      at: lastUsedAt,
    });
    await dbSaveActivationCode({
      ...entry,
      used_count: usedCount + 1,
      last_used_at: lastUsedAt,
      used_records: usedRecords,
    });

    console.log(`[USER] Registered: ${normalizedUsername}, phone: ${phone || 'N/A'}`);
    res.json({ code: 200, msg: '注册成功' });
  } catch (e) {
    console.error('[register]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 用户登录（用户名+密码）
// POST /api/user/login
// ───────────────────────────────────────────────────────
app.post('/api/user/login', async (req, res) => {
  try {
    const { username, password, activation_code, agreed_terms_version, agreed_privacy_version, agreed_time } = req.body || {};
    const normalizedUsername = normalizeUsername(username);
    if (!normalizedUsername || !password)
      return res.status(400).json({ code: 400, msg: '用户名和密码不能为空' });
    if (!isValidUsername(normalizedUsername))
      return res.status(400).json({ code: 400, msg: '用户名只能包含中文、英文和数字' });

    const user = await dbGetUser(normalizedUsername);
    if (!user) return res.status(401).json({ code: 401, msg: '用户名或密码错误' });

    const passwordMatch = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatch)
      return res.status(401).json({ code: 401, msg: '用户名或密码错误' });

    if (user.activation_code_hash) {
      const entry = await dbGetActivationCode(user.activation_code_hash);
      if (!entry) return res.status(403).json({ code: 403, msg: '激活码无效' });
      if (entry.revoked) return res.status(403).json({ code: 403, msg: '激活码已被禁用' });
      const expiresMs = entry.expires_at ? Date.parse(entry.expires_at) : NaN;
      if (!Number.isNaN(expiresMs) && Date.now() > expiresMs) {
        if (!activation_code)
          return res.status(403).json({ code: 403, msg: '激活码已过期' });
        const applied = await applyActivationCodeForUser({
          activationCode: activation_code,
          username: normalizedUsername,
          phone: user.phone,
          req,
        });
        if (!applied.ok) return res.status(403).json({ code: 403, msg: applied.msg });
        user.activation_code_hash = applied.codeHash;
        user.activated = true;
      }
    }

    const versionConfig = loadVersionConfig();
    const latestTermsVersion = versionConfig.android?.full?.latestTermsVersion || '1.0';
    const latestPrivacyVersion = versionConfig.android?.full?.latestPrivacyVersion || '1.0';
    const effectiveTermsVersion = agreed_terms_version || user.agreed_terms_version || '0.0';
    const effectivePrivacyVersion = agreed_privacy_version || user.agreed_privacy_version || '0.0';
    if (
      compareVersion(effectiveTermsVersion, latestTermsVersion) < 0 ||
      compareVersion(effectivePrivacyVersion, latestPrivacyVersion) < 0
    ) {
      return res.status(403).json({
        code: 403, msg: '需同意最新用户协议与隐私政策',
        latest_terms_version: latestTermsVersion, latest_privacy_version: latestPrivacyVersion,
      });
    }

    const token = generateUserToken();
    const tokenVersion = (Number.isFinite(user.token_version) ? user.token_version : 0);
    const newTokenVersion = tokenVersion >= TOKEN_VERSION_MAX ? 1 : tokenVersion + 1;

    await dbSaveUser({
      ...user,
      token: token,
      token_version: newTokenVersion,
      last_login: new Date().toISOString(),
      agreed_terms_version: agreed_terms_version || user.agreed_terms_version,
      agreed_privacy_version: agreed_privacy_version || user.agreed_privacy_version,
      agreed_time: agreed_time || user.agreed_time,
    });

    const bindDeviceId = req.headers['x-device-id'];
    if (bindDeviceId) {
      const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
      await dbUpsertDevice(bindDeviceId, bindIp, null, null, null, user.username, user.phone, 'full');
    }
    await wsKickUserDevices({
      username: user.username,
      phone: user.phone,
      excludeDeviceId: bindDeviceId,
      reason: '账号已在其他设备登录',
    });

    console.log(`[USER] Login: ${normalizedUsername}`);
    res.json({
      code: 200, token, token_version: newTokenVersion,
      user: { username: user.username, phone: user.phone },
    });
  } catch (e) {
    console.error('[login]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 发送短信验证码（模拟）
// POST /api/user/sms/send
// ───────────────────────────────────────────────────────
app.post('/api/user/sms/send', (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  const normalizedPhone = String(phone).trim();
  if (!normalizedPhone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });

  const code = '123456'; // 模拟验证码
  smsCodeStore.set(normalizedPhone, { code, expireAt: Date.now() + SMS_CODE_EXPIRE_MS });
  console.log(`[SMS] Sent code to ${normalizedPhone}: ${code} (mock)`);
  res.json({ code: 200, msg: '验证码已发送' });
});

// ───────────────────────────────────────────────────────
// 手机号+验证码登录
// POST /api/user/sms/login
// ───────────────────────────────────────────────────────
app.post('/api/user/sms/login', async (req, res) => {
  try {
    const { phone, code, activation_code, agreed_terms_version, agreed_privacy_version, agreed_time } = req.body || {};
    if (!phone || !code)
      return res.status(400).json({ code: 400, msg: '手机号和验证码不能为空' });

    const normalizedPhone = String(phone).trim();
    const normalizedCode = String(code).trim();
    if (!normalizedPhone || !normalizedCode)
      return res.status(400).json({ code: 400, msg: '手机号和验证码不能为空' });

    const stored = smsCodeStore.get(normalizedPhone);
    if (!stored || stored.code !== normalizedCode)
      return res.status(401).json({ code: 401, msg: '验证码错误' });
    if (Date.now() > stored.expireAt) {
      smsCodeStore.delete(normalizedPhone);
      return res.status(401).json({ code: 401, msg: '验证码已过期' });
    }
    smsCodeStore.delete(normalizedPhone);

    const user = await dbGetUserByPhone(normalizedPhone);
    if (!user) return res.status(401).json({ code: 401, msg: '该手机号未注册' });

    if (user.activation_code_hash) {
      const entry = await dbGetActivationCode(user.activation_code_hash);
      if (!entry) return res.status(403).json({ code: 403, msg: '激活码无效' });
      if (entry.revoked) return res.status(403).json({ code: 403, msg: '激活码已被禁用' });
      const expiresMs = entry.expires_at ? Date.parse(entry.expires_at) : NaN;
      if (!Number.isNaN(expiresMs) && Date.now() > expiresMs) {
        if (!activation_code)
          return res.status(403).json({ code: 403, msg: '激活码已过期' });
        const applied = await applyActivationCodeForUser({
          activationCode: activation_code,
          username: user.username,
          phone: normalizedPhone,
          req,
        });
        if (!applied.ok) return res.status(403).json({ code: 403, msg: applied.msg });
        user.activation_code_hash = applied.codeHash;
        user.activated = true;
      }
    }

    const versionConfig = loadVersionConfig();
    const latestTermsVersion = versionConfig.android?.full?.latestTermsVersion || '1.0';
    const latestPrivacyVersion = versionConfig.android?.full?.latestPrivacyVersion || '1.0';
    const effectiveTermsVersion = agreed_terms_version || user.agreed_terms_version || '0.0';
    const effectivePrivacyVersion = agreed_privacy_version || user.agreed_privacy_version || '0.0';
    if (
      compareVersion(effectiveTermsVersion, latestTermsVersion) < 0 ||
      compareVersion(effectivePrivacyVersion, latestPrivacyVersion) < 0
    ) {
      return res.status(403).json({
        code: 403, msg: '需同意最新用户协议与隐私政策',
        latest_terms_version: latestTermsVersion, latest_privacy_version: latestPrivacyVersion,
      });
    }

    const token = generateUserToken();
    const tokenVersion = Number.isFinite(user.token_version) ? user.token_version : 0;
    const newTokenVersion = tokenVersion >= TOKEN_VERSION_MAX ? 1 : tokenVersion + 1;

    await dbSaveUser({
      ...user,
      token: token,
      token_version: newTokenVersion,
      last_login: new Date().toISOString(),
      agreed_terms_version: agreed_terms_version || user.agreed_terms_version,
      agreed_privacy_version: agreed_privacy_version || user.agreed_privacy_version,
      agreed_time: agreed_time || user.agreed_time,
    });

    const bindDeviceId = req.headers['x-device-id'];
    if (bindDeviceId) {
      const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
      await dbUpsertDevice(bindDeviceId, bindIp, null, null, null, user.username, user.phone, 'full');
    }
    await wsKickUserDevices({
      username: user.username,
      phone: user.phone,
      excludeDeviceId: bindDeviceId,
      reason: '账号已在其他设备登录',
    });

    console.log(`[USER] SMS Login: ${normalizedPhone} => ${user.username}`);
    res.json({
      code: 200, token, token_version: newTokenVersion,
      user: { username: user.username, phone: user.phone },
    });
  } catch (e) {
    console.error('[sms/login]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// Token 验证
// POST /api/user/token/verify
// ───────────────────────────────────────────────────────
app.post('/api/user/token/verify', async (req, res) => {
  try {
    const { token } = req.body || {};
    if (!token) return res.status(400).json({ code: 400, msg: '缺少 token' });

    const user = await dbGetUserByToken(token);
    if (!user) return res.status(401).json({ code: 401, msg: '登录已失效' });

    const clientVersion = parseInt(req.body?.token_version ?? 0, 10);
    let serverVersion = Number.isFinite(user.token_version) ? user.token_version : 1;
    if (serverVersion > TOKEN_VERSION_MAX) {
      serverVersion = 1;
      await dbSaveUser({ ...user, token_version: 1 });
    }
    if (clientVersion !== serverVersion)
      return res.status(401).json({ code: 401, msg: '登录已失效' });

    res.json({
      code: 200, token_version: serverVersion,
      user: { username: user.username, phone: user.phone },
    });
  } catch (e) {
    console.error('[token/verify]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 忘记密码：手机号+验证码重置密码
// POST /api/user/password/reset
// ───────────────────────────────────────────────────────
app.post('/api/user/password/reset', async (req, res) => {
  try {
    const { phone, sms_code, new_password } = req.body || {};
    if (!phone || !sms_code || !new_password)
      return res.status(400).json({ code: 400, msg: '手机号、验证码和新密码不能为空' });

    const normalizedPhone = String(phone).trim();
    const normalizedSmsCode = String(sms_code).trim();
    const newPassword = String(new_password);

    if (!normalizedPhone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });
    if (!normalizedSmsCode) return res.status(400).json({ code: 400, msg: '验证码不能为空' });
    if (!newPassword) return res.status(400).json({ code: 400, msg: '新密码不能为空' });
    if (newPassword.length < 6) return res.status(400).json({ code: 400, msg: '密码长度不能少于6位' });

    const stored = smsCodeStore.get(normalizedPhone);
    if (!stored || stored.code !== normalizedSmsCode)
      return res.status(401).json({ code: 401, msg: '验证码错误' });
    if (Date.now() > stored.expireAt) {
      smsCodeStore.delete(normalizedPhone);
      return res.status(401).json({ code: 401, msg: '验证码已过期' });
    }
    smsCodeStore.delete(normalizedPhone);

    const user = await dbGetUserByPhone(normalizedPhone);
    if (!user) return res.status(404).json({ code: 404, msg: '该手机号未注册' });

    const tokenVersion = Number.isFinite(user.token_version) ? user.token_version : 0;
    const newTokenVersion = tokenVersion >= TOKEN_VERSION_MAX ? 1 : tokenVersion + 1;
    await dbSaveUser({
      ...user,
      password_hash: await bcrypt.hash(newPassword, 12),
      token: '',
      token_version: newTokenVersion,
      password_updated_at: new Date().toISOString(),
    });
    await wsKickUserDevices({
      username: user.username,
      phone: user.phone,
      reason: '密码已重置，请重新登录',
    });

    console.log(`[USER] Reset password: ${normalizedPhone} => ${user.username}`);
    res.json({ code: 200, msg: '密码已重置' });
  } catch (e) {
    console.error('[password/reset]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 版本检查接口（APP 调用）
// POST /api/version/check
// ───────────────────────────────────────────────────────
app.post('/api/version/check', async (req, res) => {
  try {
    const { os, os_version, arch, app_version, password, permissions } = req.body || {};
    const deviceId = req.headers['x-device-id'] || 'unknown';
    const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    const rawClientType = req.body?.client_type || req.body?.clientType;
    let normalizedClientType = rawClientType ? normalizeVersionClientType(rawClientType) : null;
    if (!normalizedClientType && deviceId !== 'unknown') {
      const existing = await dbGetDevice(deviceId);
      if (existing?.client_type) normalizedClientType = normalizeVersionClientType(existing.client_type);
    }

    const decryptedPw = password ? decryptPassword(password) : null;
    const device = await dbUpsertDevice(
      deviceId, ip, app_version, decryptedPw, permissions, null, null, normalizedClientType
    );

    console.log(JSON.stringify({ time: new Date().toISOString(), deviceId, ip, os, os_version, arch, app_version }));

    if (device.banned) return res.json({ banned: true, msg: '设备已被禁用，请联系管理员' });

    const versionConfig = loadVersionConfig();
    const resolvedClientType = normalizedClientType || device?.client_type || 'full';
    const cfg = versionConfig.android[resolvedClientType] || versionConfig.android.full;
    const effectiveAppVersion = app_version || device?.app_version || '';

    if (cfg.minRequired && effectiveAppVersion && compareVersion(effectiveAppVersion, cfg.minRequired) < 0) {
      const label = resolvedClientType === 'share_only' ? '用户版' : resolvedClientType === 'desktop' ? '桌面版' : '完整版';
      return res.json({
        banned: true,
        msg: `${label}当前版本 ${effectiveAppVersion} 低于最低要求版本 ${cfg.minRequired}，已拒绝连接`,
        minRequired: cfg.minRequired,
        latestVersion: cfg.latestVersion,
        latestTermsVersion: cfg.latestTermsVersion,
        latestPrivacyVersion: cfg.latestPrivacyVersion,
        forceUpdate: true,
        downloadUrl: cfg.downloadUrl,
        updateLog: cfg.updateLog,
        url: cfg.releaseUrl,
        clientType: resolvedClientType,
      });
    }

    return res.json({
      url: cfg.releaseUrl,
      latestVersion: cfg.latestVersion,
      latestTermsVersion: cfg.latestTermsVersion,
      latestPrivacyVersion: cfg.latestPrivacyVersion,
      minRequired: cfg.minRequired,
      forceUpdate: cfg.forceUpdate,
      downloadUrl: cfg.downloadUrl,
      updateLog: cfg.updateLog,
      clientType: resolvedClientType,
    });
  } catch (e) {
    console.error('[version/check]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 远控会话上报接口（APP 端调用）
// POST /api/session/start | heartbeat | end
// ───────────────────────────────────────────────────────
app.post('/api/session/start', async (req, res) => {
  try {
    const { session_id, peer_id, username, phone } = req.body || {};
    const deviceId = req.headers['x-device-id'] || 'unknown';
    const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    if (!session_id) return res.status(400).json({ code: 400, msg: '缺少 session_id' });

    await dbUpsertDevice(deviceId, ip);

    // 若 peer_id 存在，尝试从对端设备获取用户信息
    let resolvedUsername = username || null;
    let resolvedPhone = phone || null;
    if (peer_id && (!resolvedUsername || !resolvedPhone)) {
      const peerDevice = await dbGetDevice(peer_id);
      if (peerDevice) {
        resolvedUsername = resolvedUsername || peerDevice.username || null;
        resolvedPhone = resolvedPhone || peerDevice.phone || null;
      }
    }

    await dbAddSession(deviceId, session_id, peer_id, resolvedUsername, resolvedPhone);

    console.log(`[SESSION START] device=${deviceId} session=${session_id} peer=${peer_id}`);
    res.json({ code: 200, msg: 'ok' });
  } catch (e) {
    console.error('[session/start]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/api/session/heartbeat', async (req, res) => {
  try {
    const { session_id } = req.body || {};
    const deviceId = req.headers['x-device-id'] || 'unknown';
    const device = await dbGetDevice(deviceId);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    await dbUpdateSessionHeartbeat(deviceId, session_id);
    res.json({ code: 200, msg: 'ok' });
  } catch (e) {
    console.error('[session/heartbeat]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/api/session/end', async (req, res) => {
  try {
    const { session_id } = req.body || {};
    const deviceId = req.headers['x-device-id'] || 'unknown';
    const device = await dbGetDevice(deviceId);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    await dbEndSession(deviceId, session_id);
    console.log(`[SESSION END] device=${deviceId} session=${session_id}`);
    res.json({ code: 200, msg: 'ok' });
  } catch (e) {
    console.error('[session/end]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 管理 API
// ───────────────────────────────────────────────────────
app.post('/admin/login', (req, res) => {
  const { password } = req.body;
  console.log(`[LOGIN] Received pw (first 16): ${(password || '').substring(0, 16)}...`);
  if (password === ADMIN_PASSWORD_HASH || password === ADMIN_RAW_PASSWORD) {
    return res.json({ code: 200, token: SESSION_TOKEN });
  }
  return res.status(401).json({ code: 401, msg: '密码错误' });
});

app.get('/admin/users', authMiddleware, async (req, res) => {
  try {
    const list = await dbListUsers(req.query.q);
    res.json({ code: 200, data: list, total: list.length });
  } catch (e) {
    console.error('[admin/users]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.delete('/admin/users/:username', authMiddleware, async (req, res) => {
  try {
    const normalizedUsername = normalizeUsername(req.params.username);
    if (!normalizedUsername)
      return res.status(400).json({ code: 400, msg: '缺少用户名' });
    const user = await dbGetUser(normalizedUsername);
    if (!user) return res.status(404).json({ code: 404, msg: '用户不存在' });
    await dbDeleteUser(normalizedUsername);
    res.json({ code: 200, msg: '已删除' });
  } catch (e) {
    console.error('[admin/users DELETE]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// 获取设备列表（附带远控状态 & 版本信息）
app.get('/admin/devices', authMiddleware, async (req, res) => {
  try {
    const devices = await dbGetAllDevices();
    const list = await Promise.all(devices.map(async d => {
      const sessions = await dbGetDeviceSessions(d.id, 20);
      return mapDevice(d, sessions);
    }));
    res.json({ code: 200, data: list });
  } catch (e) {
    console.error('[admin/devices]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// 获取单个设备详情
app.get('/admin/devices/:id', authMiddleware, async (req, res) => {
  try {
    const device = await dbGetDevice(req.params.id);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    const sessions = await dbGetDeviceSessions(device.id);
    res.json({ code: 200, data: mapDevice(device, sessions) });
  } catch (e) {
    console.error('[admin/devices/:id]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/admin/devices/:id/ban', authMiddleware, async (req, res) => {
  try {
    const device = await dbGetDevice(req.params.id);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    await dbSetDeviceBanned(req.params.id, true);
    wsPushToDevice(req.params.id, { action: 'banned', msg: '设备已被管理员禁用远程功能' });
    res.json({ code: 200, msg: '已禁用' });
  } catch (e) {
    console.error('[admin/devices ban]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/admin/devices/:id/unban', authMiddleware, async (req, res) => {
  try {
    const device = await dbGetDevice(req.params.id);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    await dbSetDeviceBanned(req.params.id, false);
    wsPushToDevice(req.params.id, { action: 'unbanned', msg: '远程功能已恢复' });
    res.json({ code: 200, msg: '已恢复' });
  } catch (e) {
    console.error('[admin/devices unban]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.delete('/admin/devices/:id', authMiddleware, async (req, res) => {
  try {
    const device = await dbGetDevice(req.params.id);
    if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
    await dbDeleteDevice(req.params.id);
    wsPushToDevice(req.params.id, { action: 'banned', msg: '设备记录已被删除' });
    wsCloseDevice(req.params.id);
    res.json({ code: 200, msg: '已删除' });
  } catch (e) {
    console.error('[admin/devices DELETE]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/admin/users/reset-password', authMiddleware, async (req, res) => {
  try {
    const { username, phone, password, random } = req.body || {};
    const normalizedUsername = normalizeUsername(username);
    if (!normalizedUsername && !phone)
      return res.status(400).json({ code: 400, msg: '缺少用户名或手机号' });

    let newPassword = String(password || '');
    if (random) newPassword = crypto.randomBytes(6).toString('hex');
    if (!newPassword) return res.status(400).json({ code: 400, msg: '缺少新密码' });
    if (newPassword.length < 6) return res.status(400).json({ code: 400, msg: '密码长度不能少于6位' });

    let user = null;
    if (normalizedUsername) user = await dbGetUser(normalizedUsername);
    if (!user && phone) user = await dbGetUserByPhone(phone);
    if (!user) return res.status(404).json({ code: 404, msg: '用户不存在' });

    const tokenVersion = Number.isFinite(user.token_version) ? user.token_version : 0;
    const newTokenVersion = tokenVersion >= TOKEN_VERSION_MAX ? 1 : tokenVersion + 1;
    await dbSaveUser({
      ...user,
      password_hash: await bcrypt.hash(newPassword, 12),
      token: '',
      token_version: newTokenVersion,
      password_updated_at: new Date().toISOString(),
    });
    await wsKickUserDevices({
      username: user.username,
      phone: user.phone,
      reason: '管理员已重置密码，请重新登录',
    });
    res.json({ code: 200, msg: '密码已重置', data: { password: newPassword } });
  } catch (e) {
    console.error('[admin/reset-password]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

// ───────────────────────────────────────────────────────
// 版本管理 API
// ───────────────────────────────────────────────────────
app.get('/admin/version', authMiddleware, (req, res) => {
  const clientType = normalizeVersionClientType(req.query.client_type);
  const config = loadVersionConfig();
  res.json({ code: 200, data: config.android[clientType], clientType });
});

app.post('/admin/version', authMiddleware, (req, res) => {
  const body = req.body || {};
  const clientType = normalizeVersionClientType(body.clientType);
  const config = loadVersionConfig();
  mergeVersionFields(config.android[clientType], body);
  saveVersionConfig(config);
  console.log(`[VERSION] Config updated [${clientType}]:`, JSON.stringify(config.android[clientType]));
  res.json({ code: 200, msg: '版本配置已更新', data: config.android[clientType], clientType });
});

app.post('/admin/version/upload', authMiddleware, (req, res) => {
  const clientType = getVersionClientTypeFromReq(req);
  uploadApk.single('apk')(req, res, (err) => {
    if (err) {
      console.error('[UPLOAD] Error:', err.message);
      return res.status(400).json({ code: 400, msg: err.message });
    }
    if (!req.file) return res.status(400).json({ code: 400, msg: '未选择文件' });
    const filename = req.file.filename;
    const downloadPath = `/download/${clientType}/${encodeURIComponent(filename)}`;
    console.log(`[UPLOAD] APK uploaded [${clientType}]: ${filename} (${(req.file.size / 1024 / 1024).toFixed(1)}MB)`);
    res.json({ code: 200, msg: '上传成功', data: { filename, size: req.file.size, downloadPath, clientType } });
  });
});

app.get('/admin/version/files', authMiddleware, (req, res) => {
  const clientType = getVersionClientTypeFromReq(req);
  const apkDir = getApkDirByClientType(clientType);
  const ext = clientType === 'desktop' ? '.exe' : '.apk';
  try {
    const files = fs.readdirSync(apkDir)
      .filter(f => f.toLowerCase().endsWith(ext))
      .map(f => {
        const stat = fs.statSync(path.join(apkDir, f));
        return { filename: f, size: stat.size, modified: stat.mtime.toISOString() };
      })
      .sort((a, b) => new Date(b.modified) - new Date(a.modified));
    res.json({ code: 200, data: files, clientType });
  } catch { res.json({ code: 200, data: [] }); }
});

app.delete('/admin/version/files/:filename', authMiddleware, (req, res) => {
  const clientType = getVersionClientTypeFromReq(req);
  const apkDir = getApkDirByClientType(clientType);
  const ext = clientType === 'desktop' ? '.exe' : '.apk';
  const raw = String(req.params.filename || '');
  const filename = path.basename(raw);
  if (!filename || filename !== raw || !filename.toLowerCase().endsWith(ext))
    return res.status(400).json({ code: 400, msg: '文件名不合法' });
  const filePath = path.join(apkDir, filename);
  if (!fs.existsSync(filePath)) return res.status(404).json({ code: 404, msg: '文件不存在' });
  try {
    fs.unlinkSync(filePath);
    res.json({ code: 200, msg: '已删除' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: e.message || '删除失败' });
  }
});

// ───────────────────────────────────────────────────────
// 激活码管理 API
// ───────────────────────────────────────────────────────
app.get('/admin/activation-codes', authMiddleware, async (req, res) => {
  try {
    const nowMs = Date.now();
    const rows = await dbGetAllActivationCodes();
    const list = rows
      .filter(e => !e.revoked) // 已撤销的不展示
      .map(e => {
        const maxUses = Number.isFinite(e.max_uses) ? e.max_uses : 1;
        const usedCount = Number.isFinite(e.used_count) ? e.used_count : 0;
        const expiresMs = e.expires_at ? Date.parse(e.expires_at) : NaN;
        const expired = !Number.isNaN(expiresMs) && nowMs > expiresMs;
        const usedUp = usedCount >= maxUses;
        const status = expired ? 'expired' : usedUp ? 'used_up' : 'active';
        return {
          hash: e.hash,
          createdAt: e.created_at || null,
          expiresAt: e.expires_at || null,
          maxUses,
          usedCount,
          status,
          note: e.note || '',
          lastUsedAt: e.last_used_at || null,
          revokedAt: null,
        };
      })
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    res.json({ code: 200, data: list });
  } catch (e) {
    console.error('[admin/activation-codes GET]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/admin/activation-codes', authMiddleware, async (req, res) => {
  try {
    const { count, expiresInDays, expiresAt, maxUses, note, length } = req.body || {};
    const n = Math.min(Math.max(parseInt(count || 1, 10), 1), 200);
    const max = Math.min(Math.max(parseInt(maxUses || 1, 10), 1), 10000);
    const codeLen = Math.min(Math.max(parseInt(length || 16, 10), 8), 64);

    let expiresAtIso = null;
    if (expiresAt) {
      const t = Date.parse(expiresAt);
      if (!Number.isNaN(t)) expiresAtIso = new Date(t).toISOString();
    } else if (expiresInDays !== undefined) {
      const days = Math.min(Math.max(parseInt(expiresInDays || 0, 10), 0), 3650);
      if (days > 0) expiresAtIso = new Date(Date.now() + days * 86400000).toISOString();
    }

    const createdAt = new Date().toISOString();
    const created = [];

    for (let i = 0; i < n; i++) {
      let code = '', hash = '';
      for (let retry = 0; retry < 10; retry++) {
        code = generateActivationCode({ length: codeLen, group: 4 });
        hash = hashActivationCode(normalizeActivationCode(code));
        if (!(await dbGetActivationCode(hash))) break;
        hash = '';
      }
      if (!hash) return res.status(500).json({ code: 500, msg: '生成激活码失败，请重试' });

      await dbSaveActivationCode({
        hash,
        created_at: createdAt,
        expires_at: expiresAtIso,
        max_uses: max,
        used_count: 0,
        revoked: false,
        revoked_at: null,
        note: note ? String(note) : '',
        last_used_at: null,
        used_records: [],
      });
      created.push({ code, hash, expiresAt: expiresAtIso, maxUses: max });
    }

    res.json({ code: 200, data: created });
  } catch (e) {
    console.error('[admin/activation-codes POST]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.post('/admin/activation-codes/revoke', authMiddleware, async (req, res) => {
  try {
    const { hash } = req.body || {};
    if (!hash) return res.status(400).json({ code: 400, msg: '缺少 hash' });
    const entry = await dbGetActivationCode(hash);
    if (!entry) return res.status(404).json({ code: 404, msg: '激活码不存在' });
    await dbDeleteActivationCode(hash);
    res.json({ code: 200, msg: '已删除' });
  } catch (e) {
    console.error('[admin/activation-codes/revoke]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.get('/health', (_req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));
app.get('/admin', (_req, res) => res.sendFile(path.join(__dirname, 'admin.html')));

// ───────────────────────────────────────────────────────
// WebSocket 工具函数
// ───────────────────────────────────────────────────────
async function wsKickUserDevices({ username, phone, excludeDeviceId, reason }) {
  const devices = await dbGetDevicesByUser(username, phone);
  if (!devices.length) return;
  const payload = {
    action: 'login_kick',
    msg: reason || '账号已在其他设备登录',
  };
  for (const device of devices) {
    const deviceId = device?.id;
    if (!deviceId) continue;
    if (excludeDeviceId && deviceId === excludeDeviceId) continue;
    wsPushToDevice(deviceId, payload);
  }
}

function wsPushToDevice(deviceId, data) {
  const sockets = wsClients.get(deviceId);
  if (!sockets) return;
  const msg = JSON.stringify(data);
  for (const ws of sockets) {
    if (ws.readyState === WebSocket.OPEN) ws.send(msg);
  }
}

function wsCloseDevice(deviceId) {
  const sockets = wsClients.get(deviceId);
  if (!sockets) return;
  for (const ws of sockets) ws.close();
  wsClients.delete(deviceId);
}

// ───────────────────────────────────────────────────────
// 启动 HTTP + WebSocket 服务
// ───────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', async (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get('id') || req.headers['x-device-id'] || '';
  if (!deviceId) { ws.close(1008, 'Missing device id'); return; }

  if (!wsClients.has(deviceId)) wsClients.set(deviceId, new Set());
  wsClients.get(deviceId).add(ws);
  console.log(`[WS] Device connected: ${deviceId} (total: ${wsClients.get(deviceId).size})`);

  try {
    const device = await dbGetDevice(deviceId);
    if (device?.banned) {
      ws.send(JSON.stringify({ action: 'banned', msg: '设备已被管理员禁用远程功能' }));
    } else {
      ws.send(JSON.stringify({ action: 'unbanned', msg: '远程功能正常' }));
    }
  } catch { /* 忽略 */ }

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('close', () => {
    const sockets = wsClients.get(deviceId);
    if (sockets) {
      sockets.delete(ws);
      if (sockets.size === 0) wsClients.delete(deviceId);
    }
    console.log(`[WS] Device disconnected: ${deviceId}`);
  });
  ws.on('error', (err) => console.error(`[WS] Error for ${deviceId}:`, err.message));
});

const wsHeartbeat = setInterval(() => {
  wss.clients.forEach(ws => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);
wss.on('close', () => clearInterval(wsHeartbeat));

// ───────────────────────────────────────────────────────
// 等待 SQLite 初始化完成后再启动服务
// ───────────────────────────────────────────────────────
(async () => {
  try {
    await initSQLiteDatabase(__dirname);
    server.listen(PORT, () => {
      console.log(`✅ 服务运行在 :${PORT}`);
      console.log(`   管理界面   : http://localhost:${PORT}/admin`);
      console.log(`   版本检查   : POST /api/version/check`);
      console.log(`   会话上报   : POST /api/session/start | heartbeat | end`);
      console.log(`   WebSocket  : ws://localhost:${PORT}/ws?id=DEVICE_ID`);
    });
  } catch (err) {
    console.error('[FATAL] SQLite 初始化失败:', err);
    process.exit(1);
  }
})();