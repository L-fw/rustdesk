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
const ADMIN_PASSWORD = 'your-password-here'; // ← 改成你的密码
const DATA_FILE = path.join(__dirname, 'devices.json');

const VERSION_CONFIG = {
  android: {
    latestVersion: '1.4.5',
    minRequired: '1.4.5',
    forceUpdate: false,
    downloadUrl: 'http://112.74.59.152/download/rustdesk-latest.apk',
    updateLog: '1. 修复连接稳定性问题\n2. 优化画面传输质量',
    releaseUrl: 'http://112.74.59.152/releases/tag/1.4.5',
  },
};

// ───────────────────────────────────────────────────────
// 设备数据管理（存 JSON 文件）
// 格式：{ "device_id": { name, firstSeen, lastSeen, banned } }
// ───────────────────────────────────────────────────────
function loadDevices() {
  if (!fs.existsSync(DATA_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveDevices(devices) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(devices, null, 2));
}

function upsertDevice(deviceId, ip) {
  const devices = loadDevices();
  const now = new Date().toISOString();
  if (!devices[deviceId]) {
    devices[deviceId] = {
      id: deviceId,
      firstSeen: now,
      lastSeen: now,
      ip,
      banned: false,
    };
  } else {
    devices[deviceId].lastSeen = now;
    devices[deviceId].ip = ip;
  }
  saveDevices(devices);
  return devices[deviceId];
}

// ───────────────────────────────────────────────────────
// 管理员认证中间件
// ───────────────────────────────────────────────────────
function authMiddleware(req, res, next) {
  const token = req.headers['x-admin-token'];
  if (token !== ADMIN_PASSWORD) {
    return res.status(401).json({ code: 401, msg: '未授权' });
  }
  next();
}

// ───────────────────────────────────────────────────────
// 版本检查接口（APP 调用）
// POST /api/version/check
// Header: X-Device-Id
// ───────────────────────────────────────────────────────
app.post('/api/version/check', (req, res) => {
  const { os, os_version, arch, typ } = req.body || {};
  const deviceId = req.headers['x-device-id'] || 'unknown';
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  // 记录设备
  const device = upsertDevice(deviceId, ip);

  // 日志
  console.log(JSON.stringify({
    time: new Date().toISOString(),
    deviceId, ip, os, os_version, arch,
  }));

  // 设备被禁用
  if (device.banned) {
    return res.json({ banned: true, msg: '设备已被禁用，请联系管理员' });
  }

  // 返回版本信息
  return res.json({
    url: VERSION_CONFIG.android.releaseUrl,
  });
});

// ───────────────────────────────────────────────────────
// 管理 API
// ───────────────────────────────────────────────────────

// 登录验证
app.post('/admin/login', (req, res) => {
  const { password } = req.body;
  if (password === ADMIN_PASSWORD) {
    return res.json({ code: 200, token: ADMIN_PASSWORD });
  }
  return res.status(401).json({ code: 401, msg: '密码错误' });
});

// 获取设备列表
app.get('/admin/devices', authMiddleware, (req, res) => {
  const devices = loadDevices();
  const list = Object.values(devices).sort(
    (a, b) => new Date(b.lastSeen) - new Date(a.lastSeen)
  );
  res.json({ code: 200, data: list });
});

// 禁用设备
app.post('/admin/devices/:id/ban', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) {
    return res.status(404).json({ code: 404, msg: '设备不存在' });
  }
  devices[req.params.id].banned = true;
  saveDevices(devices);
  res.json({ code: 200, msg: '已禁用' });
});

// 恢复设备
app.post('/admin/devices/:id/unban', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) {
    return res.status(404).json({ code: 404, msg: '设备不存在' });
  }
  devices[req.params.id].banned = false;
  saveDevices(devices);
  res.json({ code: 200, msg: '已恢复' });
});

// 删除设备记录
app.delete('/admin/devices/:id', authMiddleware, (req, res) => {
  const devices = loadDevices();
  if (!devices[req.params.id]) {
    return res.status(404).json({ code: 404, msg: '设备不存在' });
  }
  delete devices[req.params.id];
  saveDevices(devices);
  res.json({ code: 200, msg: '已删除' });
});

// 健康检查
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// ───────────────────────────────────────────────────────
// 管理界面（静态 HTML）
// ───────────────────────────────────────────────────────
app.get('/admin', (_req, res) => {
  res.sendFile(path.join(__dirname, 'admin.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ 服务运行在 :${PORT}`);
  console.log(`   管理界面: http://localhost:${PORT}/admin`);
  console.log(`   版本检查: POST http://localhost:${PORT}/api/version/check`);
});