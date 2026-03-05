// ═══════════════════════════════════════════════════════
// RustDesk 设备管理后台 + 版本检查 API
// 端口：3000
// ═══════════════════════════════════════════════════════

const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const crypto = require('crypto');
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
const DATA_FILE = path.join(__dirname, 'devices.json');
const VERSION_FILE = path.join(__dirname, 'version.json');
const APK_DIR = path.join(__dirname, 'apk');

// 心跳超时：超过此时间没有心跳视为会话已断开（毫秒）
const SESSION_TIMEOUT_MS = 90 * 1000; // 90秒

// 确保 APK 目录存在
if (!fs.existsSync(APK_DIR)) fs.mkdirSync(APK_DIR, { recursive: true });

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

function upsertDevice(deviceId, ip, appVersion, password, permissions) {
  const devices = loadDevices();
  const now = new Date().toISOString();
  if (!devices[deviceId]) {
    devices[deviceId] = {
      id: deviceId, firstSeen: now, lastSeen: now,
      ip, banned: false,
      appVersion: appVersion || null,
      password: password ? decryptPassword(password) : null,
      permissions: permissions || {},
      sessions: [],
    };
  } else {
    devices[deviceId].lastSeen = now;
    devices[deviceId].ip = ip;
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
  const { session_id, peer_id } = req.body || {};
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