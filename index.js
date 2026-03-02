// ═══════════════════════════════════════════════════════
// RustDesk 自建服务器 — 版本检查 API
// 兼容 RustDesk 原生更新机制（Rust 端 do_check_software_update）
// ═══════════════════════════════════════════════════════

const express = require('express');
const app = express();
app.use(express.json());

// ───────────────────────────────────────────────────────
// 版本配置
// latestVersion : 当前最新版本号（与 Cargo.toml / pubspec.yaml 对应）
// releaseUrl    : 发布页面 URL（版本号放在最后一段路径）
//
// RustDesk 客户端逻辑：
//   1. POST 请求，body = { os, os_version, arch, device_id, typ }
//   2. 响应 { url: "https://..." }
//   3. 从 url 的最后一个 "/" 后提取版本号，与本地版本比较
//   4. 如果服务器版本 > 本地版本 → 显示更新提示
//   5. 如果服务器版本 <= 本地版本 → 静默通过
// ───────────────────────────────────────────────────────
const VERSION_CONFIG = {
  latestVersion: '1.6.0',
  // url 格式: 最后一段路径必须是版本号，RustDesk 通过 rsplit('/') 提取
  releaseUrl: 'http://112.74.59.152/releases/tag/1.6.0',
};

// ───────────────────────────────────────────────────────
// POST /api/version/check
//
// RustDesk 原生请求格式:
//   POST body (JSON):
//   {
//     "os": "android",
//     "os_version": "14",
//     "arch": "aarch64",
//     "device_id": [...],
//     "typ": "rustdesk-client"
//   }
//
// 响应格式:
//   { "url": "https://your-domain.com/releases/tag/1.5.0" }
//
// 如果不需要更新，返回空 url 即可
// ───────────────────────────────────────────────────────
app.post('/api/version/check', (req, res) => {
  const { os, os_version, arch, typ } = req.body || {};
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  // 日志
  console.log(JSON.stringify({
    time: new Date().toISOString(),
    ip, os, os_version, arch, typ,
  }));

  // 返回最新版本的 release URL
  // RustDesk 客户端会自行比较版本号来决定是否提示更新
  return res.json({
    url: VERSION_CONFIG.releaseUrl,
  });
});

// 健康检查
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ 版本检查服务运行在 :${PORT}`);
  console.log(`   测试: curl -X POST http://localhost:${PORT}/api/version/check -H "Content-Type: application/json" -d '{"os":"android","os_version":"14","arch":"aarch64","typ":"rustdesk-client"}'`);
});
