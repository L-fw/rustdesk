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
const { initSQLiteDatabase } = require('./sqlite_db');
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
const ADMIN_RAW_PASSWORD = '    '; // ← 改成你的密码
const ADMIN_PASSWORD_HASH = crypto.createHash('sha256').update(ADMIN_RAW_PASSWORD).digest('hex');
console.log(`[AUTH] Admin password hash: ${ADMIN_PASSWORD_HASH.substring(0, 16)}...`);

// ───────────────────────────────────────────────────────
// AES 加解密工具（用于设备密码传输加密）
// ───────────────────────────────────────────────────────
const AES_KEY = Buffer.from('gamwing-rustdesk-2024-secret-k!!');	// 32 bytes
const AES_IV = Buffer.from('0123456789abcdef');						// 16 bytes

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
const DATA_FILE = path.join(__dirname, 'devices.json');
const VERSION_FILE = path.join(__dirname, 'version.json');
const USERS_FILE = path.join(__dirname, 'users.json');
const ACTIVATION_CODES_FILE = path.join(path.dirname(DATA_FILE), 'activation_codes.json');
const LEGACY_ACTIVATION_CODES_FILE = path.join(__dirname, 'version-check', 'activation_codes.json');
const APK_DIR = path.join(__dirname, 'apk');

// 心跳超时：超过此时间没有心跳视为会话已断开（毫秒）
const SESSION_TIMEOUT_MS = 90 * 1000; // 90秒

// 确保 APK 目录存在
if (!fs.existsSync(APK_DIR)) fs.mkdirSync(APK_DIR, { recursive: true });
initSQLiteDatabase(__dirname);

// ───────────────────────────────────────────────────────
// 版本配置管理（持久化到 version.json）
// ───────────────────────────────────────────────────────
const DEFAULT_VERSION_CONFIG = {
  android: {
    latestVersion: '1.8.0',
    minRequired: '1.4.5',
    forceUpdate: false,
    downloadUrl: 'http://112.74.59.152/download/rustdesk-latest.apk',
    updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
    releaseUrl: 'http://112.74.59.152/releases/tag/1.8.0',
  },
};

function loadVersionConfig() {
  if (!fs.existsSync(VERSION_FILE)) {
    saveVersionConfig(DEFAULT_VERSION_CONFIG);
    return JSON.parse(JSON.stringify(DEFAULT_VERSION_CONFIG));
  }
  try { return JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8')); }
  catch { return JSON.parse(JSON.stringify(DEFAULT_VERSION_CONFIG)); }
}

function saveVersionConfig(config) {
  fs.writeFileSync(VERSION_FILE, JSON.stringify(config, null, 2));
}

// multer 配置：APK 上传
const apkStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, APK_DIR),
  filename: (_req, file, cb) => {
    // 保留原始文件名，如有同名则覆盖
    cb(null, file.originalname);
  },
});
const uploadApk = multer({
  storage: apkStorage,
  limits: { fileSize: 200 * 1024 * 1024 }, // 最大 200MB
  fileFilter: (_req, file, cb) => {
    if (file.originalname.toLowerCase().endsWith('.apk')) cb(null, true);
    else cb(new Error('只允许上传 .apk 文件'));
  },
});

// 静态文件服务：提供 APK 下载
app.use('/download', express.static(APK_DIR));

// ───────────────────────────────────────────────────────
// 设备数据管理
// 格式：{
//   "device_id": {
//     id, firstSeen, lastSeen, ip, banned,
//     appVersion,          ← 客户端上报的软件版本
//     sessions: [          ← 远控会话记录
//       { sessionId, peerId, startTime, lastHeartbeat, ended, endTime }
//     ]
//   }
// }
// ───────────────────────────────────────────────────────
function loadDevices() {
  if (!fs.existsSync(DATA_FILE)) return {};
  try { return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); }
  catch { return {}; }
}

function saveDevices(devices) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(devices, null, 2));
}

function upsertDevice(deviceId, ip, appVersion, password, permissions, username, phone) {
  const devices = loadDevices();
  const now = new Date().toISOString();
  if (!devices[deviceId]) {
    devices[deviceId] = {
      id: deviceId, firstSeen: now, lastSeen: now,
      ip, banned: false,
      username: username || null,
      phone: phone || null,
      appVersion: appVersion || null,
      password: password ? decryptPassword(password) : null,
      permissions: permissions || {},
      sessions: [],
    };
  } else {
    devices[deviceId].lastSeen = now;
    devices[deviceId].ip = ip;
    if (username) devices[deviceId].username = username;
    if (phone) devices[deviceId].phone = phone;
    if (appVersion) devices[deviceId].appVersion = appVersion;
    if (password) devices[deviceId].password = decryptPassword(password);
    if (permissions && typeof permissions === 'object') devices[deviceId].permissions = permissions;
    if (!devices[deviceId].sessions) devices[deviceId].sessions = [];
    if (!devices[deviceId].permissions) devices[deviceId].permissions = {};
  }
  saveDevices(devices);
  return devices[deviceId];
}

// 判断设备是否正在远控（有活跃心跳的未结束会话）
function isRemoting(device) {
  if (!device.sessions?.length) return false;
  const now = Date.now();
  return device.sessions.some(s => {
    if (s.ended) return false;
    return now - new Date(s.lastHeartbeat || s.startTime).getTime() < SESSION_TIMEOUT_MS;
  });
}

function getActiveSessions(device) {
  if (!device.sessions?.length) return [];
  const now = Date.now();
  return device.sessions.filter(s => {
    if (s.ended) return false;
    return now - new Date(s.lastHeartbeat || s.startTime).getTime() < SESSION_TIMEOUT_MS;
  });
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
// 用户数据管理
// ───────────────────────────────────────────────────────
function loadUsers() {
  if (!fs.existsSync(USERS_FILE)) return {};
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return {}; }
}

function saveUsers(users) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
}

function loadActivationCodes() {
  if (!fs.existsSync(ACTIVATION_CODES_FILE)) return {};
  try { return JSON.parse(fs.readFileSync(ACTIVATION_CODES_FILE, 'utf8')); }
  catch { return {}; }
}

function saveActivationCodes(codes) {
  fs.writeFileSync(ACTIVATION_CODES_FILE, JSON.stringify(codes, null, 2));
}

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
  for (let i = 0; i < length; i++) {
    raw += alphabet[bytes[i] % alphabet.length];
  }
  if (!group || group <= 0) return raw;
  const parts = [];
  for (let i = 0; i < raw.length; i += group) parts.push(raw.slice(i, i + group));
  return parts.join('-');
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
// Body: { username, password, phone, sms_code, activation_code }
// ───────────────────────────────────────────────────────
app.post('/api/user/register', (req, res) => {
  const { username, password, phone, sms_code, activation_code } = req.body || {};

  if (!username || !password) {
    return res.status(400).json({ code: 400, msg: '用户名和密码不能为空' });
  }
  if (!phone) {
    return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  }
  if (!sms_code) {
    return res.status(400).json({ code: 400, msg: '验证码不能为空' });
  }
  if (!activation_code) {
    return res.status(400).json({ code: 400, msg: '激活码不能为空' });
  }

  const normalizedPhone = String(phone).trim();
  const normalizedSmsCode = String(sms_code).trim();
  if (!normalizedPhone) {
    return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  }
  if (!normalizedSmsCode) {
    return res.status(400).json({ code: 400, msg: '验证码不能为空' });
  }

  const users = loadUsers();
  if (users[username]) {
    return res.status(400).json({ code: 400, msg: '用户名已存在' });
  }

  // 检查手机号是否已注册
  const existingUser = Object.values(users).find(u => u.phone === normalizedPhone);
  if (existingUser) {
    return res.status(400).json({ code: 400, msg: '该手机号已被注册' });
  }

  const storedSms = smsCodeStore.get(normalizedPhone);
  if (!storedSms || storedSms.code !== normalizedSmsCode) {
    return res.status(401).json({ code: 401, msg: '验证码错误' });
  }
  if (Date.now() > storedSms.expireAt) {
    smsCodeStore.delete(normalizedPhone);
    return res.status(401).json({ code: 401, msg: '验证码已过期' });
  }
  smsCodeStore.delete(normalizedPhone);

  const normalizedCode = normalizeActivationCode(activation_code);
  if (!normalizedCode) {
    return res.status(400).json({ code: 400, msg: '激活码不能为空' });
  }

  const codeHash = hashActivationCode(normalizedCode);
  const codes = loadActivationCodes();
  const entry = codes[codeHash];
  if (!entry) {
    return res.status(400).json({ code: 400, msg: '激活码无效' });
  }
  if (entry.revoked) {
    return res.status(400).json({ code: 400, msg: '激活码已被禁用' });
  }
  const nowMs = Date.now();
  const expiresMs = entry.expiresAt ? Date.parse(entry.expiresAt) : NaN;
  if (!Number.isNaN(expiresMs) && nowMs > expiresMs) {
    return res.status(400).json({ code: 400, msg: '激活码已过期' });
  }
  const maxUses = Number.isFinite(entry.maxUses) ? entry.maxUses : 1;
  const usedCount = Number.isFinite(entry.usedCount) ? entry.usedCount : 0;
  if (usedCount >= maxUses) {
    return res.status(400).json({ code: 400, msg: '激活码已被使用' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  users[username] = {
    username,
    password_hash: passwordHash,
    phone: normalizedPhone,
    activation_code_hash: codeHash,
    activated: true,
    created_at: new Date().toISOString(),
    token_version: 1,
  };
  saveUsers(users);

  const bindDeviceId = req.headers['x-device-id'];
  if (bindDeviceId) {
    const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
    upsertDevice(bindDeviceId, bindIp, null, null, null, username, normalizedPhone);
  }

  entry.usedCount = usedCount + 1;
  entry.lastUsedAt = new Date().toISOString();
  if (!Array.isArray(entry.usedRecords)) entry.usedRecords = [];
  entry.usedRecords.push({
    username,
    phone: phone || '',
    ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
    at: entry.lastUsedAt,
  });
  codes[codeHash] = entry;
  saveActivationCodes(codes);

  console.log(`[USER] Registered: ${username}, phone: ${phone || 'N/A'}`);
  res.json({ code: 200, msg: '注册成功' });
});

// ───────────────────────────────────────────────────────
// 用户登录接口（用户名+密码）
// POST /api/user/login
// Body: { username, password }
// ───────────────────────────────────────────────────────
app.post('/api/user/login', (req, res) => {
  const { username, password } = req.body || {};

  if (!username || !password) {
    return res.status(400).json({ code: 400, msg: '用户名和密码不能为空' });
  }

  const users = loadUsers();
  const user = users[username];
  if (!user) {
    return res.status(401).json({ code: 401, msg: '用户名或密码错误' });
  }

  const passwordHash = crypto.createHash('sha256').update(password).digest('hex');
  if (user.password_hash !== passwordHash) {
    return res.status(401).json({ code: 401, msg: '用户名或密码错误' });
  }

  const token = generateUserToken();
  if (!user.token_version || !Number.isFinite(user.token_version)) {
    user.token_version = 1;
  }
  user.token_version = user.token_version >= TOKEN_VERSION_MAX ? 1 : user.token_version + 1;
  // 存储 token 到用户信息
  user.token = token;
  user.last_login = new Date().toISOString();
  saveUsers(users);

  const bindDeviceId = req.headers['x-device-id'];
  if (bindDeviceId) {
    const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
    upsertDevice(bindDeviceId, bindIp, null, null, null, user.username, user.phone);
  }

  console.log(`[USER] Login: ${username}`);
  res.json({
    code: 200,
    token,
    token_version: user.token_version,
    user: { username: user.username, phone: user.phone },
  });
});

// ───────────────────────────────────────────────────────
// 发送短信验证码（模拟）
// POST /api/user/sms/send
// Body: { phone }
// ───────────────────────────────────────────────────────
app.post('/api/user/sms/send', (req, res) => {
  const { phone } = req.body || {};
  if (!phone) {
    return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  }

  const normalizedPhone = String(phone).trim();
  if (!normalizedPhone) {
    return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  }

  // 模拟验证码：固定 123456
  const code = '123456';
  smsCodeStore.set(normalizedPhone, {
    code,
    expireAt: Date.now() + SMS_CODE_EXPIRE_MS,
  });

  console.log(`[SMS] Sent code to ${normalizedPhone}: ${code} (mock)`);
  res.json({ code: 200, msg: '验证码已发送' });
});

// ───────────────────────────────────────────────────────
// 手机号+验证码登录
// POST /api/user/sms/login
// Body: { phone, code }
// ───────────────────────────────────────────────────────
app.post('/api/user/sms/login', (req, res) => {
  const { phone, code } = req.body || {};
  if (!phone || !code) {
    return res.status(400).json({ code: 400, msg: '手机号和验证码不能为空' });
  }

  const normalizedPhone = String(phone).trim();
  const normalizedCode = String(code).trim();
  if (!normalizedPhone || !normalizedCode) {
    return res.status(400).json({ code: 400, msg: '手机号和验证码不能为空' });
  }

  // 验证码校验
  const stored = smsCodeStore.get(normalizedPhone);
  if (!stored || stored.code !== normalizedCode) {
    return res.status(401).json({ code: 401, msg: '验证码错误' });
  }
  if (Date.now() > stored.expireAt) {
    smsCodeStore.delete(normalizedPhone);
    return res.status(401).json({ code: 401, msg: '验证码已过期' });
  }
  smsCodeStore.delete(normalizedPhone);

  // 查找对应手机号的用户
  const users = loadUsers();
  const user = Object.values(users).find(u => u.phone === normalizedPhone);
  if (!user) {
    return res.status(401).json({ code: 401, msg: '该手机号未注册' });
  }

  const token = generateUserToken();
  if (!user.token_version || !Number.isFinite(user.token_version)) {
    user.token_version = 1;
  }
  user.token_version = user.token_version >= TOKEN_VERSION_MAX ? 1 : user.token_version + 1;
  user.token = token;
  user.last_login = new Date().toISOString();
  saveUsers(users);

  const bindDeviceId = req.headers['x-device-id'];
  if (bindDeviceId) {
    const bindIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
    upsertDevice(bindDeviceId, bindIp, null, null, null, user.username, user.phone);
  }

  console.log(`[USER] SMS Login: ${normalizedPhone} => ${user.username}`);
  res.json({
    code: 200,
    token,
    token_version: user.token_version,
    user: { username: user.username, phone: user.phone },
  });
});

app.post('/api/user/token/verify', (req, res) => {
  const { token } = req.body || {};
  if (!token) {
    return res.status(400).json({ code: 400, msg: '缺少 token' });
  }
  const users = loadUsers();
  const user = Object.values(users).find(u => u.token === token);
  if (!user) {
    return res.status(401).json({ code: 401, msg: '登录已失效' });
  }
  const clientVersion = parseInt(req.body?.token_version ?? 0, 10);
  let serverVersion = Number.isFinite(user.token_version) ? user.token_version : 1;
  if (serverVersion > TOKEN_VERSION_MAX) {
    serverVersion = 1;
    user.token_version = 1;
    saveUsers(users);
  }
  if (clientVersion !== serverVersion) {
    return res.status(401).json({ code: 401, msg: '登录已失效' });
  }
  res.json({
    code: 200,
    token_version: serverVersion,
    user: { username: user.username, phone: user.phone },
  });
});

// ───────────────────────────────────────────────────────
// 忘记密码：手机号+验证码重置密码
// POST /api/user/password/reset
// Body: { phone, sms_code, new_password }
// ───────────────────────────────────────────────────────
app.post('/api/user/password/reset', (req, res) => {
  const { phone, sms_code, new_password } = req.body || {};
  if (!phone || !sms_code || !new_password) {
    return res
        .status(400)
        .json({ code: 400, msg: '手机号、验证码和新密码不能为空' });
  }

  const normalizedPhone = String(phone).trim();
  const normalizedSmsCode = String(sms_code).trim();
  const newPassword = String(new_password);

  if (!normalizedPhone) {
    return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  }
  if (!normalizedSmsCode) {
    return res.status(400).json({ code: 400, msg: '验证码不能为空' });
  }
  if (!newPassword) {
    return res.status(400).json({ code: 400, msg: '新密码不能为空' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ code: 400, msg: '密码长度不能少于6位' });
  }

  const stored = smsCodeStore.get(normalizedPhone);
  if (!stored || stored.code !== normalizedSmsCode) {
    return res.status(401).json({ code: 401, msg: '验证码错误' });
  }
  if (Date.now() > stored.expireAt) {
    smsCodeStore.delete(normalizedPhone);
    return res.status(401).json({ code: 401, msg: '验证码已过期' });
  }
  smsCodeStore.delete(normalizedPhone);

  const users = loadUsers();
  const user = Object.values(users).find(u => u.phone === normalizedPhone);
  if (!user) {
    return res.status(404).json({ code: 404, msg: '该手机号未注册' });
  }

  user.password_hash =
      crypto.createHash('sha256').update(newPassword).digest('hex');
  user.token = '';
  if (!user.token_version || !Number.isFinite(user.token_version)) {
    user.token_version = 1;
  }
  user.token_version = user.token_version >= TOKEN_VERSION_MAX ? 1 : user.token_version + 1;
  user.password_updated_at = new Date().toISOString();
  saveUsers(users);

  console.log(`[USER] Reset password: ${normalizedPhone} => ${user.username}`);
  res.json({ code: 200, msg: '密码已重置' });
});

// ───────────────────────────────────────────────────────
// 版本检查接口（APP 调用）
// POST /api/version/check
// Header: X-Device-Id
// Body:   { os, os_version, arch, app_version }   ← 新增 app_version
// ───────────────────────────────────────────────────────
app.post('/api/version/check', (req, res) => {
  const { os, os_version, arch, app_version, password, permissions } = req.body || {};
  const deviceId = req.headers['x-device-id'] || 'unknown';
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  const device = upsertDevice(deviceId, ip, app_version, password, permissions);

  console.log(JSON.stringify({ time: new Date().toISOString(), deviceId, ip, os, os_version, arch, app_version }));

  if (device.banned) return res.json({ banned: true, msg: '设备已被禁用，请联系管理员' });

  const versionConfig = loadVersionConfig();
  const cfg = versionConfig.android;
  return res.json({
    url: cfg.releaseUrl,
    latestVersion: cfg.latestVersion,
    minRequired: cfg.minRequired,
    forceUpdate: cfg.forceUpdate,
    downloadUrl: cfg.downloadUrl,
    updateLog: cfg.updateLog,
  });
});

// ───────────────────────────────────────────────────────
// 远控会话上报接口（APP 端调用）
//
// POST /api/session/start      开始被控
//   Header: X-Device-Id
//   Body:   { session_id, peer_id }
//
// POST /api/session/heartbeat  心跳保活（建议每 30 秒一次）
//   Header: X-Device-Id
//   Body:   { session_id }
//
// POST /api/session/end        结束被控
//   Header: X-Device-Id
//   Body:   { session_id }
// ───────────────────────────────────────────────────────
app.post('/api/session/start', (req, res) => {
  const { session_id, peer_id, username, phone } = req.body || {};
  const deviceId = req.headers['x-device-id'] || 'unknown';
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  if (!session_id) return res.status(400).json({ code: 400, msg: '缺少 session_id' });

  // 确保设备存在
  upsertDevice(deviceId, ip);
  const devices = loadDevices();
  const device = devices[deviceId];
  const now = new Date().toISOString();

  if (!device.sessions.find(s => s.sessionId === session_id)) {
    device.sessions.push({
      sessionId: session_id,
      peerId: peer_id || null,
      username: username || device.username || null,
      phone: phone || device.phone || null,
      startTime: now,
      lastHeartbeat: now,
      ended: false,
      endTime: null,
    });
    // 只保留最近 200 条历史
    if (device.sessions.length > 200) device.sessions = device.sessions.slice(-200);
    saveDevices(devices);
  }

  console.log(`[SESSION START] device=${deviceId} session=${session_id} peer=${peer_id}`);
  res.json({ code: 200, msg: 'ok' });
});

app.post('/api/session/heartbeat', (req, res) => {
  const { session_id } = req.body || {};
  const deviceId = req.headers['x-device-id'] || 'unknown';
  const devices = loadDevices();
  const device = devices[deviceId];
  if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });

  const s = device.sessions?.find(s => s.sessionId === session_id);
  if (s) { s.lastHeartbeat = new Date().toISOString(); saveDevices(devices); }
  res.json({ code: 200, msg: 'ok' });
});

app.post('/api/session/end', (req, res) => {
  const { session_id } = req.body || {};
  const deviceId = req.headers['x-device-id'] || 'unknown';
  const devices = loadDevices();
  const device = devices[deviceId];
  if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });

  const s = device.sessions?.find(s => s.sessionId === session_id);
  if (s) { s.ended = true; s.endTime = new Date().toISOString(); saveDevices(devices); }

  console.log(`[SESSION END] device=${deviceId} session=${session_id}`);
  res.json({ code: 200, msg: 'ok' });
});

// ───────────────────────────────────────────────────────
// 管理 API
// ───────────────────────────────────────────────────────
app.post('/admin/login', (req, res) => {
  const { password } = req.body;
  console.log(`[LOGIN] Received pw (first 16): ${(password || '').substring(0, 16)}... Expected hash (first 16): ${ADMIN_PASSWORD_HASH.substring(0, 16)}...`);
  // 支持 SHA256 哈希密码（新版客户端）和明文密码（兼容旧版/调试）
  if (password === ADMIN_PASSWORD_HASH || password === ADMIN_RAW_PASSWORD) {
    return res.json({ code: 200, token: SESSION_TOKEN });
  }
  return res.status(401).json({ code: 401, msg: '密码错误' });
});

// 获取设备列表（附带远控状态 & 版本信息）
app.get('/admin/devices', authMiddleware, (req, res) => {
  const devices = loadDevices();
  const list = Object.values(devices)
    .sort((a, b) => new Date(b.lastSeen) - new Date(a.lastSeen))
    .map(d => ({
      ...d,
      remoting: isRemoting(d),
      activeSessions: getActiveSessions(d),
      sessions: (d.sessions || []).slice(-20), // 只返回最近 20 条历史
    }));
  res.json({ code: 200, data: list });
});

// 获取单个设备详情
app.get('/admin/devices/:id', authMiddleware, (req, res) => {
  const devices = loadDevices();
  const device = devices[req.params.id];
  if (!device) return res.status(404).json({ code: 404, msg: '设备不存在' });
  res.json({
    code: 200,
    data: {
      ...device,
      remoting: isRemoting(device),
      activeSessions: getActiveSessions(device),
    },
  });
});

app.post('/admin/devices/:id/ban', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) return res.status(404).json({ code: 404, msg: '设备不存在' });
  devices[req.params.id].banned = true;
  saveDevices(devices);
  // WebSocket 即时推送
  wsPushToDevice(req.params.id, { action: 'banned', msg: '设备已被管理员禁用远程功能' });
  res.json({ code: 200, msg: '已禁用' });
});

app.post('/admin/devices/:id/unban', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) return res.status(404).json({ code: 404, msg: '设备不存在' });
  devices[req.params.id].banned = false;
  saveDevices(devices);
  // WebSocket 即时推送
  wsPushToDevice(req.params.id, { action: 'unbanned', msg: '远程功能已恢复' });
  res.json({ code: 200, msg: '已恢复' });
});

app.delete('/admin/devices/:id', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) return res.status(404).json({ code: 404, msg: '设备不存在' });
  delete devices[req.params.id];
  saveDevices(devices);
  // 推送禁用并关闭 WebSocket
  wsPushToDevice(req.params.id, { action: 'banned', msg: '设备记录已被删除' });
  wsCloseDevice(req.params.id);
  res.json({ code: 200, msg: '已删除' });
});

app.post('/admin/users/reset-password', authMiddleware, (req, res) => {
  const { username, phone, password, random } = req.body || {};
  if (!username && !phone) {
    return res.status(400).json({ code: 400, msg: '缺少用户名或手机号' });
  }
  let newPassword = String(password || '');
  if (random) {
    newPassword = crypto.randomBytes(6).toString('hex');
  }
  if (!newPassword) {
    return res.status(400).json({ code: 400, msg: '缺少新密码' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ code: 400, msg: '密码长度不能少于6位' });
  }
  const users = loadUsers();
  let user = null;
  if (username && users[username]) user = users[username];
  if (!user && phone) {
    user = Object.values(users).find(u => u.phone === phone) || null;
  }
  if (!user) return res.status(404).json({ code: 404, msg: '用户不存在' });

  user.password_hash = crypto.createHash('sha256').update(newPassword).digest('hex');
  user.token = '';
  if (!user.token_version || !Number.isFinite(user.token_version)) {
    user.token_version = 1;
  }
  user.token_version = user.token_version >= TOKEN_VERSION_MAX ? 1 : user.token_version + 1;
  user.password_updated_at = new Date().toISOString();
  saveUsers(users);
  res.json({ code: 200, msg: '密码已重置', data: { password: newPassword } });
});

// ───────────────────────────────────────────────────────
// 版本管理 API（管理后台调用）
// ───────────────────────────────────────────────────────

// 获取版本配置
app.get('/admin/version', authMiddleware, (req, res) => {
  const config = loadVersionConfig();
  res.json({ code: 200, data: config.android });
});

// 更新版本配置
app.post('/admin/version', authMiddleware, (req, res) => {
  const { latestVersion, minRequired, forceUpdate, downloadUrl, updateLog, releaseUrl } = req.body || {};
  const config = loadVersionConfig();
  if (latestVersion !== undefined) config.android.latestVersion = latestVersion;
  if (minRequired !== undefined) config.android.minRequired = minRequired;
  if (forceUpdate !== undefined) config.android.forceUpdate = !!forceUpdate;
  if (downloadUrl !== undefined) config.android.downloadUrl = downloadUrl;
  if (updateLog !== undefined) config.android.updateLog = updateLog;
  if (releaseUrl !== undefined) config.android.releaseUrl = releaseUrl;
  saveVersionConfig(config);
  console.log(`[VERSION] Config updated:`, JSON.stringify(config.android));
  res.json({ code: 200, msg: '版本配置已更新', data: config.android });
});

// 上传 APK 文件
app.post('/admin/version/upload', authMiddleware, (req, res) => {
  uploadApk.single('apk')(req, res, (err) => {
    if (err) {
      console.error('[UPLOAD] Error:', err.message);
      return res.status(400).json({ code: 400, msg: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ code: 400, msg: '未选择文件' });
    }
    const filename = req.file.filename;
    const downloadPath = `/download/${encodeURIComponent(filename)}`;
    console.log(`[UPLOAD] APK uploaded: ${filename} (${(req.file.size / 1024 / 1024).toFixed(1)}MB)`);
    res.json({
      code: 200,
      msg: '上传成功',
      data: { filename, size: req.file.size, downloadPath },
    });
  });
});

// 获取已上传的 APK 文件列表
app.get('/admin/version/files', authMiddleware, (req, res) => {
  try {
    const files = fs.readdirSync(APK_DIR)
      .filter(f => f.toLowerCase().endsWith('.apk'))
      .map(f => {
        const stat = fs.statSync(path.join(APK_DIR, f));
        return { filename: f, size: stat.size, modified: stat.mtime.toISOString() };
      })
      .sort((a, b) => new Date(b.modified) - new Date(a.modified));
    res.json({ code: 200, data: files });
  } catch { res.json({ code: 200, data: [] }); }
});

app.delete('/admin/version/files/:filename', authMiddleware, (req, res) => {
  const raw = String(req.params.filename || '');
  const filename = path.basename(raw);
  if (!filename || filename !== raw || !filename.toLowerCase().endsWith('.apk')) {
    return res.status(400).json({ code: 400, msg: '文件名不合法' });
  }
  const filePath = path.join(APK_DIR, filename);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ code: 404, msg: '文件不存在' });
  }
  try {
    fs.unlinkSync(filePath);
    res.json({ code: 200, msg: '已删除' });
  } catch (e) {
    res.status(500).json({ code: 500, msg: e.message || '删除失败' });
  }
});

app.get('/admin/activation-codes', authMiddleware, (req, res) => {
  const nowMs = Date.now();
  const codes = loadActivationCodes();
  let mutated = false;
  for (const [hash, e] of Object.entries(codes)) {
    if (e && e.revoked) {
      delete codes[hash];
      mutated = true;
    }
  }
  if (mutated) saveActivationCodes(codes);
  const list = Object.entries(codes).map(([hash, e]) => {
    const maxUses = Number.isFinite(e.maxUses) ? e.maxUses : 1;
    const usedCount = Number.isFinite(e.usedCount) ? e.usedCount : 0;
    const expiresMs = e.expiresAt ? Date.parse(e.expiresAt) : NaN;
    const expired = !Number.isNaN(expiresMs) && nowMs > expiresMs;
    const usedUp = usedCount >= maxUses;
    const status = expired ? 'expired' : usedUp ? 'used_up' : 'active';
    return {
      hash,
      createdAt: e.createdAt || null,
      expiresAt: e.expiresAt || null,
      maxUses,
      usedCount,
      status,
      note: e.note || '',
      lastUsedAt: e.lastUsedAt || null,
      revokedAt: null,
    };
  }).sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
  res.json({ code: 200, data: list });
});

app.post('/admin/activation-codes', authMiddleware, (req, res) => {
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
    if (days > 0) expiresAtIso = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  }

  const codes = loadActivationCodes();
  const createdAt = new Date().toISOString();
  const created = [];

  for (let i = 0; i < n; i++) {
    let code = '';
    let normalized = '';
    let hash = '';
    for (let retry = 0; retry < 10; retry++) {
      code = generateActivationCode({ length: codeLen, group: 4 });
      normalized = normalizeActivationCode(code);
      hash = hashActivationCode(normalized);
      if (!codes[hash]) break;
    }
    if (!hash || codes[hash]) {
      return res.status(500).json({ code: 500, msg: '生成激活码失败，请重试' });
    }
    codes[hash] = {
      createdAt,
      expiresAt: expiresAtIso,
      maxUses: max,
      usedCount: 0,
      revoked: false,
      revokedAt: null,
      note: note ? String(note) : '',
      lastUsedAt: null,
      usedRecords: [],
    };
    created.push({ code, hash, expiresAt: expiresAtIso, maxUses: max });
  }

  saveActivationCodes(codes);
  res.json({ code: 200, data: created });
});

app.post('/admin/activation-codes/revoke', authMiddleware, (req, res) => {
  const { hash } = req.body || {};
  if (!hash) return res.status(400).json({ code: 400, msg: '缺少 hash' });
  const codes = loadActivationCodes();
  const entry = codes[hash];
  if (!entry) return res.status(404).json({ code: 404, msg: '激活码不存在' });
  delete codes[hash];
  saveActivationCodes(codes);
  res.json({ code: 200, msg: '已删除' });
});

app.get('/health', (_req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

app.get('/admin', (_req, res) => res.sendFile(path.join(__dirname, 'admin.html')));

// ───────────────────────────────────────────────────────
// WebSocket 工具函数
// ───────────────────────────────────────────────────────
function wsPushToDevice(deviceId, data) {
  const sockets = wsClients.get(deviceId);
  if (!sockets) return;
  const msg = JSON.stringify(data);
  for (const ws of sockets) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(msg);
    }
  }
}

function wsCloseDevice(deviceId) {
  const sockets = wsClients.get(deviceId);
  if (!sockets) return;
  for (const ws of sockets) {
    ws.close();
  }
  wsClients.delete(deviceId);
}

// ───────────────────────────────────────────────────────
// 启动 HTTP + WebSocket 服务
// ───────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
const server = http.createServer(app);

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  // 从 URL 参数或 header 获取 deviceId
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get('id') || req.headers['x-device-id'] || '';

  if (!deviceId) {
    ws.close(1008, 'Missing device id');
    return;
  }

  // 注册连接
  if (!wsClients.has(deviceId)) {
    wsClients.set(deviceId, new Set());
  }
  wsClients.get(deviceId).add(ws);
  console.log(`[WS] Device connected: ${deviceId} (total: ${wsClients.get(deviceId).size})`);

  // 发送当前 banned 状态
  const devices = loadDevices();
  const device = devices[deviceId];
  if (device && device.banned) {
    ws.send(JSON.stringify({ action: 'banned', msg: '设备已被管理员禁用远程功能' }));
  } else {
    ws.send(JSON.stringify({ action: 'unbanned', msg: '远程功能正常' }));
  }

  // 心跳保活
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

  ws.on('error', (err) => {
    console.error(`[WS] Error for ${deviceId}:`, err.message);
  });
});

// WebSocket 心跳检测，30 秒一次
const wsHeartbeat = setInterval(() => {
  wss.clients.forEach(ws => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => clearInterval(wsHeartbeat));

server.listen(PORT, () => {
  console.log(`✅ 服务运行在 :${PORT}`);
  console.log(`   管理界面   : http://localhost:${PORT}/admin`);
  console.log(`   版本检查   : POST /api/version/check`);
  console.log(`   会话上报   : POST /api/session/start | heartbeat | end`);
  console.log(`   WebSocket  : ws://localhost:${PORT}/ws?id=DEVICE_ID`);
});
