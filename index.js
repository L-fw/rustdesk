// ═══════════════════════════════════════════════════════
// Gamwing 设备管理后台 + 版本检查 API
// 端口：3001
// ═══════════════════════════════════════════════════════

const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const crypto = require('crypto');
const bcrypt = require('bcrypt');
const rateLimit = require('express-rate-limit');

const {
  initSQLiteDatabase,
  dbGetUser, dbGetUserByPhone, dbGetUserByToken, dbSaveUser, dbDeleteUser, dbListUsers,
  dbGetDevice, dbGetAllDevices, dbUpsertDevice, dbGetDevicesByUser, dbSetDeviceBanned, dbDeleteDevice,
  dbAddSession, dbUpdateSessionHeartbeat, dbEndSession, dbGetDeviceSessions, dbGetUserSessions,
  dbGetActivationCode, dbGetAllActivationCodes, dbSaveActivationCode, dbDeleteActivationCode,
  dbAddVersionHistory, dbGetVersionHistory,
  dbSetUserLock, dbClearUserLock,
  dbGetLockSettings, dbSaveLockSettings,
  dbGetVersionConfig, dbSaveVersionConfig,
} = require('./sqlite_db');

const app = express();
app.use(express.json());
app.set('trust proxy', 1); // 信任一层反向代理（Nginx 等），使 express-rate-limit 能正确识别真实 IP

// ───────────────────────────────────────────────────────
// IP 限流：同一 IP 15 分钟内最多 20 次
// ───────────────────────────────────────────────────────
const loginRateLimit = rateLimit({ windowMs: 15 * 60 * 1000, max: 20, standardHeaders: true, legacyHeaders: false, message: { code: 429, msg: '该IP请求过于频繁，请 15 分钟后再试' } });
app.use('/api/user/login', loginRateLimit);
app.use('/api/user/sms/login', loginRateLimit);
app.use('/api/user/sms/send', rateLimit({ windowMs: 60 * 1000, max: 3, standardHeaders: true, legacyHeaders: false }));
app.use('/api/user/register', rateLimit({ windowMs: 60 * 60 * 1000, max: 5, standardHeaders: true, legacyHeaders: false }));

// ───────────────────────────────────────────────────────
// 账号锁定：阶梯式锁定 1分钟→5分钟→30分钟→1小时
// 失败计数在内存中；锁定时间持久化到 DB（重启后仍有效）
// ───────────────────────────────────────────────────────
const loginFailCount = new Map(); // key → 当前连续失败次数

function getLockDurationMs(lockLevel) {
  const mins = getLockSettings().lockDurationsMin;
  const min = mins[Math.min(lockLevel, mins.length - 1)] ?? 1;
  return min * 60 * 1000;
}

function fmtLockRemain(ms) {
  const sec = Math.ceil(ms / 1000);
  if (sec >= 3600) return `${Math.ceil(sec / 3600)} 小时`;
  if (sec >= 60)   return `${Math.ceil(sec / 60)} 分钟`;
  return `${sec} 秒`;
}

async function checkLoginLock(key) {
  try {
    const user = await dbGetUser(key) || await dbGetUserByPhone(key);
    if (!user || !user.lock_until) return null;
    const lockMs = Date.parse(user.lock_until);
    if (isNaN(lockMs) || Date.now() > lockMs) {
      // 锁已过期，顺手清理
      await dbClearUserLock(user.username).catch(() => {});
      return null;
    }
    return `登录失败次数过多，请 ${fmtLockRemain(lockMs - Date.now())} 后再试`;
  } catch { return null; }
}

// ───────────────────────────────────────────────────────
// 企业微信 Webhook 推送（fire-and-forget，失败不影响主流程）
// ───────────────────────────────────────────────────────
const WXWORK_WEBHOOK = 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=5c877eb8-52bf-48ab-9cf3-69377aba83d3';

function notifyWxWorkLock({ username, phone, level, lockUntil, duration }) {
  const durationText = fmtLockRemain(duration);
  const lockUntilLocal = new Date(lockUntil).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' });
  const content = [
    `🔒 **账号锁定通知**`,
    `> 用户名：${username}`,
    `> 手机号：${phone || '未绑定'}`,
    `> 锁定等级：第 ${level} 次`,
    `> 锁定时长：${durationText}`,
    `> 解锁时间：${lockUntilLocal}`,
  ].join('\n');

  fetch(WXWORK_WEBHOOK, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ msgtype: 'markdown', markdown: { content } }),
  })
    .then(r => r.json())
    .then(r => { if (r.errcode !== 0) console.warn('[WXWORK] 推送失败:', r.errmsg); })
    .catch(e => console.warn('[WXWORK] 推送异常:', e.message));
}

async function recordLoginFail(key) {
  try {
    const { failThreshold } = getLockSettings();
    const count = (loginFailCount.get(key) || 0) + 1;
    if (count < failThreshold) {
      loginFailCount.set(key, count);
      return;
    }
    // 达到阈值 → 触发阶梯锁
    loginFailCount.delete(key);
    const user = await dbGetUser(key) || await dbGetUserByPhone(key);
    if (!user) return;
    const level = user.lock_level ?? 0;
    const duration = getLockDurationMs(level);
    const lockUntil = new Date(Date.now() + duration).toISOString();
    await dbSetUserLock(user.username, lockUntil, level + 1);
    console.log(`[LOCK] ${user.username} locked level=${level + 1} until=${lockUntil}`);
    if (getLockSettings().wxworkEnabled) {
      notifyWxWorkLock({ username: user.username, phone: user.phone, level: level + 1, lockUntil, duration });
    }
  } catch (e) { console.error('[recordLoginFail]', e); }
}

async function clearLoginFail(key) {
  try {
    loginFailCount.delete(key);
    const user = await dbGetUser(key) || await dbGetUserByPhone(key);
    if (user) await dbClearUserLock(user.username);
  } catch (e) { console.error('[clearLoginFail]', e); }
}

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

const SERVER_HOST = process.env.SERVER_HOST || 'jyyxt.cloud';

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

const LEGACY_ACTIVATION_CODES_FILE = path.join(__dirname, 'version-check', 'activation_codes.json');

// ───────────────────────────────────────────────────────
// 锁定策略配置（持久化到 DB settings 表，可通过管理后台修改）
// ───────────────────────────────────────────────────────
const DEFAULT_LOCK_SETTINGS = {
  failThreshold: 3,
  lockDurationsMin: [1, 5, 30, 60],
  wxworkEnabled: true,
};

// 运行时缓存，服务启动后由 initLockSettings() 从 DB 填充
let _lockSettings = { ...DEFAULT_LOCK_SETTINGS, lockDurationsMin: [...DEFAULT_LOCK_SETTINGS.lockDurationsMin] };
function getLockSettings() { return _lockSettings; }

async function initLockSettings() {
  try {
    const saved = await dbGetLockSettings();
    if (saved) _lockSettings = saved;
  } catch (e) { console.error('[LOCK_SETTINGS] 初始化失败，使用默认值:', e.message); }
}

const APK_ROOT_RELATIVE_PATH = './apk';
const APK_FULL_RELATIVE_PATH = './apk/full';
const APK_SHARE_ONLY_RELATIVE_PATH = './apk/share_only';
const APK_DESKTOP_RELATIVE_PATH = './apk/desktop';
const APK_ROOT_DIR = path.join(__dirname, APK_ROOT_RELATIVE_PATH);
const APK_DIR_FULL = path.join(__dirname, APK_FULL_RELATIVE_PATH);
const APK_DIR_SHARE_ONLY = path.join(__dirname, APK_SHARE_ONLY_RELATIVE_PATH);
const APK_DIR_DESKTOP = path.join(__dirname, APK_DESKTOP_RELATIVE_PATH);
const QR_CODE_DIR = path.join(__dirname, 'QR_code');

// 心跳超时：超过此时间没有心跳视为会话已断开（毫秒）
const SESSION_TIMEOUT_MS = 90 * 1000; // 90秒

// 确保 APK 目录和二维码目录存在
[APK_ROOT_DIR, APK_DIR_FULL, APK_DIR_SHARE_ONLY, APK_DIR_DESKTOP, QR_CODE_DIR].forEach(dir => {
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
      releaseUrl: `https://${SERVER_HOST}/releases/tech`,
    },
    share_only: {
      latestVersion: '1.8.0',
      latestTermsVersion: '1.0',
      latestPrivacyVersion: '1.0',
      minRequired: '1.4.5',
      forceUpdate: false,
      downloadUrl: '/download/share_only/rustdesk-latest.apk',
      updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
      releaseUrl: `https://${SERVER_HOST}/releases/tech`,
    },
    desktop: {
      latestVersion: '1.8.0',
      latestTermsVersion: '1.0',
      latestPrivacyVersion: '1.0',
      minRequired: '1.4.5',
      forceUpdate: false,
      downloadUrl: '/download/desktop/rustdesk-latest.exe',
      updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
      releaseUrl: `https://${SERVER_HOST}/releases/tech`,
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

// ───────────────────────────────────────────────────────
// 版本配置管理（持久化到 DB settings 表）
// ───────────────────────────────────────────────────────
let _versionConfig = cloneDefaultVersionConfig();
function loadVersionConfig() { return _versionConfig; }

async function saveVersionConfig(config) {
  _versionConfig = config;
  await dbSaveVersionConfig(config);
}

async function initVersionConfig() {
  try {
    const saved = await dbGetVersionConfig();
    if (saved) {
      _versionConfig = normalizeVersionConfig(saved);
    } else {
      // 首次启动：若 version.json 仍存在则迁移，否则用默认值写入 DB
      const fs_mod = require('fs');
      const versionFilePath = path.join(__dirname, 'version.json');
      if (fs_mod.existsSync(versionFilePath)) {
        try {
          const parsed = JSON.parse(fs_mod.readFileSync(versionFilePath, 'utf8'));
          _versionConfig = normalizeVersionConfig(parsed);
          console.log('[VERSION] 已从 version.json 迁移配置到数据库');
        } catch { _versionConfig = cloneDefaultVersionConfig(); }
      }
      await dbSaveVersionConfig(_versionConfig);
    }
  } catch (e) { console.error('[VERSION] 初始化失败，使用默认值:', e.message); }
}

// multer 配置：APK 上传
const apkStorage = multer.diskStorage({
  destination: (req, _file, cb) =>
    cb(null, getApkDirByClientType(getVersionClientTypeFromReq(req))),
  filename: (_req, file, cb) => {
    // 修复中文文件名乱码：multer 默认用 latin1，需转为 utf8
    const filename = Buffer.from(file.originalname, 'latin1').toString('utf8');
    cb(null, filename);
  },
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
app.use('/download/qrcode', express.static(QR_CODE_DIR));
app.use('/download', express.static(APK_DIR_FULL));

// multer 配置：二维码图片上传
const QR_IMAGE_EXTS = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
const QR_CONFIG_FILE = path.join(QR_CODE_DIR, 'config.json');

const qrImageStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, QR_CODE_DIR),
  filename: (_req, file, cb) => {
    const filename = Buffer.from(file.originalname, 'latin1').toString('utf8');
    cb(null, filename);
  },
});
const uploadQrImage = multer({
  storage: qrImageStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const name = file.originalname.toLowerCase();
    if (QR_IMAGE_EXTS.some(ext => name.endsWith(ext))) cb(null, true);
    else cb(new Error('只允许上传图片文件 (png/jpg/jpeg/gif/webp)'));
  },
});

function loadQrConfig() {
  try {
    if (fs.existsSync(QR_CONFIG_FILE)) return JSON.parse(fs.readFileSync(QR_CONFIG_FILE, 'utf8'));
  } catch {}
  return { dayFile: '', nightFile: '' };
}

function saveQrConfigToFile(config) {
  fs.writeFileSync(QR_CONFIG_FILE, JSON.stringify(config, null, 2));
}

// ───────────────────────────────────────────────────────
// 公开二维码路由（固定 URL，内容由后台配置决定）
// ───────────────────────────────────────────────────────
function serveQrImage(shift, req, res) {
  const config = loadQrConfig();
  const filename = shift === 'day' ? config.dayFile : config.nightFile;
  if (!filename) return res.status(404).json({ code: 404, msg: `${shift === 'day' ? '白班' : '晚班'}二维码尚未配置` });
  const filePath = path.join(QR_CODE_DIR, path.basename(filename));
  if (!fs.existsSync(filePath)) return res.status(404).json({ code: 404, msg: '图片文件不存在，请重新上传' });
  res.sendFile(filePath);
}

app.get('/qrcode/day',   (req, res) => serveQrImage('day',   req, res));
app.get('/qrcode/night', (req, res) => serveQrImage('night', req, res));

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

    const lockMsg = await checkLoginLock(normalizedUsername);
    if (lockMsg) return res.status(429).json({ code: 429, msg: lockMsg });

    const user = await dbGetUser(normalizedUsername);
    if (!user) return res.status(401).json({ code: 401, msg: '用户名不存在，请输入正确的用户名' });

    const passwordMatch = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatch) {
      await recordLoginFail(normalizedUsername);
      return res.status(401).json({ code: 401, msg: '用户名或密码错误' });
    }
    await clearLoginFail(normalizedUsername);

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
// 发送短信验证码（阿里云短信服务）
// POST /api/user/sms/send
// ───────────────────────────────────────────────────────
const Dysmsapi = require('@alicloud/dysmsapi20170525');
const OpenApi  = require('@alicloud/openapi-client');

function createSmsClient() {
  const Credential = require('@alicloud/credentials');
  const credConfig = new Credential.Config({
    type:     'ecs_ram_role',
    roleName: 'jyyxt.cloud',
  });
  const credClient = new Credential.default(credConfig);
  const config = new OpenApi.Config({});
  config.credential = credClient;
  config.endpoint = 'dysmsapi.aliyuncs.com';
  return new Dysmsapi.default(config);
}

app.post('/api/user/sms/send', async (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });
  const normalizedPhone = String(phone).trim();
  if (!normalizedPhone) return res.status(400).json({ code: 400, msg: '手机号不能为空' });

  const code = String(Math.floor(100000 + Math.random() * 900000));

  try {
    const client = createSmsClient();
    const sendReq = new Dysmsapi.SendSmsRequest({
      phoneNumbers:  normalizedPhone,
      signName:      '深圳市佳影寰球科技',
      templateCode:  'SMS_504750157',
      templateParam: JSON.stringify({ code }),
    });
    const resp = await client.sendSms(sendReq);
    if (resp.body?.code !== 'OK') {
      console.error('[SMS] 发送失败:', resp.body);
      return res.status(500).json({ code: 500, msg: `短信发送失败: ${resp.body?.message}` });
    }
    smsCodeStore.set(normalizedPhone, { code, expireAt: Date.now() + SMS_CODE_EXPIRE_MS });
    console.log(`[SMS] Sent to ${normalizedPhone} (aliyun)`);
    res.json({ code: 200, msg: '验证码已发送' });
  } catch (e) {
    console.error('[SMS] 异常:', e.message);
    res.status(500).json({ code: 500, msg: '短信服务异常，请稍后重试' });
  }
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

    const lockMsg = await checkLoginLock(normalizedPhone);
    if (lockMsg) return res.status(429).json({ code: 429, msg: lockMsg });

    const stored = smsCodeStore.get(normalizedPhone);
    if (!stored || stored.code !== normalizedCode) {
      await recordLoginFail(normalizedPhone);
      return res.status(401).json({ code: 401, msg: '验证码错误' });
    }
    if (Date.now() > stored.expireAt) {
      smsCodeStore.delete(normalizedPhone);
      return res.status(401).json({ code: 401, msg: '验证码已过期' });
    }
    smsCodeStore.delete(normalizedPhone);
    await clearLoginFail(normalizedPhone);

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

app.get('/admin/users/:username/sessions', authMiddleware, async (req, res) => {
  try {
    const username = normalizeUsername(req.params.username);
    if (!username) return res.status(400).json({ code: 400, msg: '缺少用户名' });
    const user = await dbGetUser(username);
    if (!user) return res.status(404).json({ code: 404, msg: '用户不存在' });
    const devices = await dbGetDevicesByUser(username, user.phone);
    const deviceIds = devices.map(d => d.id);
    const sessions = await dbGetUserSessions(deviceIds);
    res.json({ code: 200, data: sessions.map(mapSession) });
  } catch (e) {
    console.error('[admin/users sessions]', e);
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
app.post('/admin/users/unlock', authMiddleware, async (req, res) => {
  try {
    const { username, phone } = req.body || {};
    const normalizedUsername = normalizeUsername(username);
    let user = null;
    if (normalizedUsername) user = await dbGetUser(normalizedUsername);
    if (!user && phone) user = await dbGetUserByPhone(String(phone).trim());
    if (!user) return res.status(404).json({ code: 404, msg: '用户不存在' });
    await dbClearUserLock(user.username);
    loginFailCount.delete(user.username);
    loginFailCount.delete(user.phone || '');
    console.log(`[UNLOCK] Admin unlocked: ${user.username}`);
    res.json({ code: 200, msg: '账号已解锁' });
  } catch (e) {
    console.error('[admin/users/unlock]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.get('/admin/version', authMiddleware, (req, res) => {
  const clientType = normalizeVersionClientType(req.query.client_type);
  const config = loadVersionConfig();
  res.json({ code: 200, data: config.android[clientType], clientType });
});

app.post('/admin/version', authMiddleware, async (req, res) => {
  const body = req.body || {};
  const clientType = normalizeVersionClientType(body.clientType);
  const config = loadVersionConfig();
  mergeVersionFields(config.android[clientType], body);
  await saveVersionConfig(config);
  const cfg = config.android[clientType];
  // 自动写入历史版本
  try {
    await dbAddVersionHistory(clientType, cfg.latestVersion, cfg.updateLog, cfg.downloadUrl);
  } catch (e) {
    console.error('[VERSION HISTORY]', e);
  }
  console.log(`[VERSION] Config updated [${clientType}]:`, JSON.stringify(cfg));
  res.json({ code: 200, msg: '版本配置已更新', data: cfg, clientType });
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
// 二维码管理 API
// ───────────────────────────────────────────────────────
app.get('/admin/qrcode/config', authMiddleware, (req, res) => {
  res.json({ code: 200, data: loadQrConfig() });
});

app.post('/admin/qrcode/config', authMiddleware, (req, res) => {
  try {
    const current = loadQrConfig();
    const { dayFile, nightFile } = req.body || {};
    const config = {
      dayFile:   dayFile   !== undefined ? path.basename(String(dayFile).trim())   : current.dayFile,
      nightFile: nightFile !== undefined ? path.basename(String(nightFile).trim()) : current.nightFile,
    };
    saveQrConfigToFile(config);
    console.log('[QR] Config saved:', config);
    res.json({ code: 200, msg: '二维码配置已保存', data: config });
  } catch (e) {
    console.error('[admin/qrcode/config POST]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.get('/admin/qrcode/files', authMiddleware, (req, res) => {
  try {
    const files = fs.readdirSync(QR_CODE_DIR)
      .filter(f => QR_IMAGE_EXTS.some(ext => f.toLowerCase().endsWith(ext)))
      .map(f => {
        const stat = fs.statSync(path.join(QR_CODE_DIR, f));
        return { filename: f, size: stat.size, modified: stat.mtime.toISOString() };
      })
      .sort((a, b) => new Date(b.modified) - new Date(a.modified));
    res.json({ code: 200, data: files });
  } catch { res.json({ code: 200, data: [] }); }
});

app.post('/admin/qrcode/upload', authMiddleware, (req, res) => {
  uploadQrImage.single('image')(req, res, (err) => {
    if (err) {
      console.error('[QR UPLOAD] Error:', err.message);
      return res.status(400).json({ code: 400, msg: err.message });
    }
    if (!req.file) return res.status(400).json({ code: 400, msg: '未选择文件' });
    const filename = req.file.filename;
    const downloadPath = `/download/qrcode/${encodeURIComponent(filename)}`;
    console.log(`[QR UPLOAD] Image uploaded: ${filename} (${(req.file.size / 1024).toFixed(1)}KB)`);
    res.json({ code: 200, msg: '上传成功', data: { filename, size: req.file.size, downloadPath } });
  });
});

app.delete('/admin/qrcode/files/:filename', authMiddleware, (req, res) => {
  const raw = String(req.params.filename || '');
  const filename = path.basename(raw);
  const lname = filename.toLowerCase();
  if (!filename || filename !== raw || !QR_IMAGE_EXTS.some(ext => lname.endsWith(ext)))
    return res.status(400).json({ code: 400, msg: '文件名不合法' });
  const filePath = path.join(QR_CODE_DIR, filename);
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

app.post('/admin/activation-codes/revoke-batch', authMiddleware, async (req, res) => {
  try {
    const { hashes } = req.body || {};
    if (!Array.isArray(hashes) || !hashes.length)
      return res.status(400).json({ code: 400, msg: '缺少 hashes 数组' });
    const results = await Promise.allSettled(
      hashes.map(async hash => {
        const entry = await dbGetActivationCode(hash);
        if (!entry) throw new Error('not_found');
        await dbDeleteActivationCode(hash);
        return hash;
      })
    );
    const deleted = results.filter(r => r.status === 'fulfilled').length;
    const failed  = results.length - deleted;
    console.log(`[admin/activation-codes/revoke-batch] deleted=${deleted} failed=${failed}`);
    res.json({ code: 200, msg: `已删除 ${deleted} 个激活码${failed ? `，${failed} 个失败` : ''}`, deleted, failed });
  } catch (e) {
    console.error('[admin/activation-codes/revoke-batch]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.get('/admin/lock-settings', authMiddleware, (_req, res) => {
  res.json({ code: 200, data: getLockSettings() });
});

app.post('/admin/lock-settings', authMiddleware, async (req, res) => {
  try {
    const { failThreshold, lockDurationsMin, wxworkEnabled } = req.body || {};
    if (
      !Number.isFinite(failThreshold) || failThreshold < 1 ||
      !Array.isArray(lockDurationsMin) || lockDurationsMin.length !== 4 ||
      lockDurationsMin.some(v => !Number.isFinite(v) || v < 1)
    ) return res.status(400).json({ code: 400, msg: '参数无效' });

    const settings = {
      failThreshold: Math.floor(failThreshold),
      lockDurationsMin: lockDurationsMin.map(v => Math.floor(v)),
      wxworkEnabled: !!wxworkEnabled,
    };
    await dbSaveLockSettings(settings);
    _lockSettings = settings;
    loginFailCount.clear(); // 重置内存计数，避免旧阈值残留
    console.log('[LOCK_SETTINGS] 已更新:', settings);
    res.json({ code: 200, msg: '保存成功' });
  } catch (e) {
    console.error('[lock-settings POST]', e);
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

app.get('/health', (_req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

// ───────────────────────────────────────────────────────
// 微信团队域名验证文件（部署校验，无需鉴权）
// 将微信提供的验证内容保存为 603cf1d9b7ec7e82427fb424a73c8fc0.txt
// 放置在 WeChat_Verify/ 目录下（与 index.js 同级）
// ───────────────────────────────────────────────────────
app.get('/603cf1d9b7ec7e82427fb424a73c8fc0.txt', (_req, res) => {
  const filePath = path.join(__dirname, 'WeChat_Verify', '603cf1d9b7ec7e82427fb424a73c8fc0.txt');
  res.sendFile(filePath, (err) => {
    if (err) {
      console.error('[WX_VERIFY] 验证文件未找到:', filePath);
      res.status(404).send('Not found');
    }
  });
});

// ───────────────────────────────────────────────────────
// 后台路径（通过环境变量隐藏，避免被扫描发现）
// 在 compose.yaml 中设置 ADMIN_PATH 为你自己的随机路径
// 例如：ADMIN_PATH=/panel-3a7f9c1b2e
// ───────────────────────────────────────────────────────
const ADMIN_PATH = process.env.ADMIN_PATH ? process.env.ADMIN_PATH.trim() : null;
if (!ADMIN_PATH) {
  console.warn('[WARN] ADMIN_PATH 未设置，后台入口已禁用。请在环境变量中配置 ADMIN_PATH。');
} else {
  app.get(ADMIN_PATH, (_req, res) => res.sendFile(path.join(__dirname, 'admin.html')));
  console.log(`[AUTH] 后台入口已挂载到: ${ADMIN_PATH}`);
}
app.get('/releases/tech', (_req, res) => res.sendFile(path.join(__dirname, 'releases.html')));
app.get('/releases/share', (_req, res) => res.sendFile(path.join(__dirname, 'releases_share.html')));

// 技术文档页
app.use('/docs/tech/assets', express.static(path.join(__dirname, 'assets')));
app.get('/docs/tech', (_req, res) => res.sendFile(path.join(__dirname, 'tech_docs.html')));

// 公开版本信息接口（供发布页动态读取，无需鉴权）
app.get('/api/public/version', (req, res) => {
  const clientType = normalizeVersionClientType(req.query.client_type);
  const config = loadVersionConfig();
  const cfg = config.android[clientType];
  res.json({
    code: 200,
    data: {
      latestVersion: cfg.latestVersion,
      updateLog: cfg.updateLog,
      downloadUrl: cfg.downloadUrl,
      clientType,
    },
  });
});

// 公开历史版本接口
app.get('/api/public/version/history', async (req, res) => {
  try {
    const clientType = normalizeVersionClientType(req.query.client_type);
    const rows = await dbGetVersionHistory(clientType, 20);
    res.json({
      code: 200,
      data: rows.map(r => ({
        version: r.version,
        updateLog: r.update_log || '',
        downloadUrl: r.download_url || '',
        createdAt: r.created_at || '',
      })),
    });
  } catch (e) {
    res.status(500).json({ code: 500, msg: '服务器内部错误' });
  }
});

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
    await initLockSettings();
    await initVersionConfig();
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