// ═══════════════════════════════════════════════════════
// SQLite 数据库模块
// 持久连接 + 全量增删改查封装
// ═══════════════════════════════════════════════════════

const path = require('path');
const sqlite3 = require('sqlite3').verbose();

let db;

// ── Promise 封装 ───────────────────────────────────────

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {
      if (err) reject(err);
      else resolve(this); // this.lastID / this.changes
    });
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row || null);
    });
  });
}

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows || []);
    });
  });
}

function safeParseJson(str, fallback) {
  try { return JSON.parse(str); } catch { return fallback; }
}

// ── 初始化 ─────────────────────────────────────────────

function initSQLiteDatabase(baseDir) {
  const dbPath = path.join(baseDir, 'server.db');
  db = new sqlite3.Database(dbPath);

  return new Promise((resolve, reject) => {
    db.serialize(() => {
      db.run('PRAGMA journal_mode=WAL');
      db.run('PRAGMA foreign_keys=ON');

      db.run(`
        CREATE TABLE IF NOT EXISTS users (
          username             TEXT PRIMARY KEY,
          password_hash        TEXT NOT NULL,
          phone                TEXT UNIQUE NOT NULL,
          token                TEXT,
          activation_code_hash TEXT,
          activated            INTEGER DEFAULT 1,
          created_at           TEXT,
          last_login           TEXT,
          password_updated_at  TEXT,
          agreed_terms_version TEXT,
          agreed_privacy_version TEXT,
          agreed_time          TEXT,
          token_version        INTEGER DEFAULT 1
        )
      `);

      db.run(`
        CREATE TABLE IF NOT EXISTS activation_codes (
          hash         TEXT PRIMARY KEY,
          created_at   TEXT,
          expires_at   TEXT,
          max_uses     INTEGER DEFAULT 1,
          used_count   INTEGER DEFAULT 0,
          note         TEXT,
          last_used_at TEXT,
          revoked      INTEGER DEFAULT 0,
          revoked_at   TEXT,
          used_records TEXT DEFAULT '[]'
        )
      `);

      db.run(`
        CREATE TABLE IF NOT EXISTS devices (
          id          TEXT PRIMARY KEY,
          first_seen  TEXT,
          last_seen   TEXT,
          ip          TEXT,
          banned      INTEGER DEFAULT 0,
          username    TEXT,
          phone       TEXT,
          app_version TEXT,
          password    TEXT,
          client_type TEXT,
          permissions TEXT DEFAULT '{}'
        )
      `);

      db.run(`
        CREATE TABLE IF NOT EXISTS sessions (
          id             INTEGER PRIMARY KEY AUTOINCREMENT,
          device_id      TEXT NOT NULL,
          session_id     TEXT NOT NULL,
          peer_id        TEXT,
          username       TEXT,
          phone          TEXT,
          start_time     TEXT,
          last_heartbeat TEXT,
          ended          INTEGER DEFAULT 0,
          end_time       TEXT
        )
      `);

      // 给旧库兼容：尝试 ALTER TABLE 补列（若列已存在会报错，忽略即可）
      const alterIgnore = (sql) => db.run(sql, [], () => {});
      alterIgnore(`ALTER TABLE users ADD COLUMN agreed_privacy_version TEXT`);
      alterIgnore(`ALTER TABLE users ADD COLUMN token_version INTEGER DEFAULT 1`);
      alterIgnore(`ALTER TABLE devices ADD COLUMN client_type TEXT`);
      alterIgnore(`ALTER TABLE devices ADD COLUMN permissions TEXT DEFAULT '{}'`);
      alterIgnore(`ALTER TABLE activation_codes ADD COLUMN revoked INTEGER DEFAULT 0`);
      alterIgnore(`ALTER TABLE activation_codes ADD COLUMN revoked_at TEXT`);
      alterIgnore(`ALTER TABLE activation_codes ADD COLUMN used_records TEXT DEFAULT '[]'`);
      alterIgnore(`ALTER TABLE sessions ADD COLUMN username TEXT`);
      alterIgnore(`ALTER TABLE sessions ADD COLUMN phone TEXT`);

      db.run(`CREATE INDEX IF NOT EXISTS idx_sessions_device ON sessions(device_id)`, [], (err) => {
        if (err) { reject(err); return; }
        console.log(`[DB] SQLite ready: ${dbPath}`);
        resolve(db);
      });
    });
  });
}

// ── Users ──────────────────────────────────────────────

function rowToUser(row) {
  if (!row) return null;
  return { ...row, activated: !!row.activated, token_version: row.token_version ?? 1 };
}

async function dbGetUser(username) {
  return rowToUser(await get('SELECT * FROM users WHERE username = ?', [username]));
}

async function dbGetUserByPhone(phone) {
  return rowToUser(await get('SELECT * FROM users WHERE phone = ?', [phone]));
}

async function dbGetUserByToken(token) {
  if (!token) return null;
  return rowToUser(await get('SELECT * FROM users WHERE token = ?', [token]));
}

async function dbSaveUser(user) {
  await run(`
    INSERT INTO users
      (username, password_hash, phone, token, activation_code_hash, activated,
       created_at, last_login, password_updated_at,
       agreed_terms_version, agreed_privacy_version, agreed_time, token_version)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(username) DO UPDATE SET
      password_hash        = excluded.password_hash,
      phone                = excluded.phone,
      token                = excluded.token,
      activation_code_hash = excluded.activation_code_hash,
      activated            = excluded.activated,
      last_login           = excluded.last_login,
      password_updated_at  = excluded.password_updated_at,
      agreed_terms_version = excluded.agreed_terms_version,
      agreed_privacy_version = excluded.agreed_privacy_version,
      agreed_time          = excluded.agreed_time,
      token_version        = excluded.token_version
  `, [
    user.username,
    user.password_hash,
    user.phone,
    user.token || null,
    user.activation_code_hash || null,
    user.activated ? 1 : 0,
    user.created_at || null,
    user.last_login || null,
    user.password_updated_at || null,
    user.agreed_terms_version || null,
    user.agreed_privacy_version || null,
    user.agreed_time || null,
    user.token_version ?? 1,
  ]);
}

async function dbDeleteUser(username) {
  await run('DELETE FROM users WHERE username = ?', [username]);
}

async function dbListUsers(query) {
  let rows;
  if (query) {
    const q = `%${String(query).trim().toLowerCase()}%`;
    rows = await all(
      'SELECT * FROM users WHERE lower(username) LIKE ? OR lower(phone) LIKE ? ORDER BY created_at DESC',
      [q, q]
    );
  } else {
    rows = await all('SELECT * FROM users ORDER BY created_at DESC', []);
  }
  return rows.map(row => ({
    username: row.username,
    phone: row.phone || '',
    created_at: row.created_at || '',
    last_login: row.last_login || '',
    activated: !!row.activated,
    token_version: row.token_version ?? 0,
    password_updated_at: row.password_updated_at || '',
    agreed_terms_version: row.agreed_terms_version || '',
    agreed_time: row.agreed_time || '',
  }));
}

// ── Devices ────────────────────────────────────────────

function rowToDevice(row) {
  if (!row) return null;
  return {
    ...row,
    banned: !!row.banned,
    permissions: safeParseJson(row.permissions, {}),
    clientType: row.client_type || null,
  };
}

async function dbGetDevice(id) {
  return rowToDevice(await get('SELECT * FROM devices WHERE id = ?', [id]));
}

async function dbGetAllDevices() {
  const rows = await all('SELECT * FROM devices ORDER BY last_seen DESC', []);
  return rows.map(rowToDevice);
}

async function dbUpsertDevice(id, ip, appVersion, password, permissions, username, phone, clientType) {
  const now = new Date().toISOString();
  const existing = await get('SELECT id FROM devices WHERE id = ?', [id]);

  if (!existing) {
    await run(`
      INSERT INTO devices
        (id, first_seen, last_seen, ip, banned, username, phone, app_version, password, client_type, permissions)
      VALUES (?,?,?,?,0,?,?,?,?,?,?)
    `, [
      id, now, now, ip,
      username || null,
      phone || null,
      appVersion || null,
      password || null,
      clientType || null,
      JSON.stringify(permissions || {}),
    ]);
  } else {
    await run(`
      UPDATE devices SET
        last_seen   = ?,
        ip          = ?,
        username    = COALESCE(?, username),
        phone       = COALESCE(?, phone),
        app_version = COALESCE(?, app_version),
        password    = COALESCE(?, password),
        client_type = COALESCE(?, client_type),
        permissions = COALESCE(?, permissions)
      WHERE id = ?
    `, [
      now, ip,
      username || null,
      phone || null,
      appVersion || null,
      password || null,
      clientType || null,
      permissions ? JSON.stringify(permissions) : null,
      id,
    ]);
  }
  return await dbGetDevice(id);
}

async function dbGetDevicesByUser(username, phone) {
  const normalizedUsername = username ? String(username).trim() : '';
  const normalizedPhone = phone ? String(phone).trim() : '';
  if (!normalizedUsername && !normalizedPhone) return [];
  if (normalizedUsername && normalizedPhone) {
    const rows = await all(
      'SELECT * FROM devices WHERE username = ? OR phone = ? ORDER BY last_seen DESC',
      [normalizedUsername, normalizedPhone]
    );
    return rows.map(rowToDevice);
  }
  if (normalizedUsername) {
    const rows = await all(
      'SELECT * FROM devices WHERE username = ? ORDER BY last_seen DESC',
      [normalizedUsername]
    );
    return rows.map(rowToDevice);
  }
  const rows = await all(
    'SELECT * FROM devices WHERE phone = ? ORDER BY last_seen DESC',
    [normalizedPhone]
  );
  return rows.map(rowToDevice);
}

async function dbSetDeviceBanned(id, banned) {
  await run('UPDATE devices SET banned = ? WHERE id = ?', [banned ? 1 : 0, id]);
}

async function dbDeleteDevice(id) {
  await run('DELETE FROM sessions WHERE device_id = ?', [id]);
  await run('DELETE FROM devices WHERE id = ?', [id]);
}

// ── Sessions ───────────────────────────────────────────

async function dbGetDeviceSessions(deviceId, limit = 200) {
  return await all(
    'SELECT * FROM sessions WHERE device_id = ? OR peer_id = ? ORDER BY start_time DESC LIMIT ?',
    [deviceId, deviceId, limit]
  );
}

async function dbGetAllActiveSessions() {
  // 返回所有未结束的会话，按 device_id 分组方便调用方处理
  return await all('SELECT * FROM sessions WHERE ended = 0 ORDER BY start_time DESC', []);
}

async function dbAddSession(deviceId, sessionId, peerId, username, phone) {
  const now = new Date().toISOString();
  const existing = await get(
    'SELECT id FROM sessions WHERE device_id = ? AND session_id = ?',
    [deviceId, sessionId]
  );
  if (!existing) {
    await run(`
      INSERT INTO sessions
        (device_id, session_id, peer_id, username, phone, start_time, last_heartbeat, ended)
      VALUES (?,?,?,?,?,?,?,0)
    `, [deviceId, sessionId, peerId || null, username || null, phone || null, now, now]);
  }
}

async function dbUpdateSessionHeartbeat(deviceId, sessionId) {
  const now = new Date().toISOString();
  await run(
    'UPDATE sessions SET last_heartbeat = ? WHERE device_id = ? AND session_id = ? AND ended = 0',
    [now, deviceId, sessionId]
  );
}

async function dbEndSession(deviceId, sessionId) {
  const now = new Date().toISOString();
  await run(
    'UPDATE sessions SET ended = 1, end_time = ? WHERE device_id = ? AND session_id = ?',
    [now, deviceId, sessionId]
  );
}

// ── Activation Codes ───────────────────────────────────

function rowToCode(row) {
  if (!row) return null;
  return {
    ...row,
    revoked: !!row.revoked,
    max_uses: row.max_uses ?? 1,
    used_count: row.used_count ?? 0,
    used_records: safeParseJson(row.used_records, []),
  };
}

async function dbGetActivationCode(hash) {
  return rowToCode(await get('SELECT * FROM activation_codes WHERE hash = ?', [hash]));
}

async function dbGetAllActivationCodes() {
  const rows = await all('SELECT * FROM activation_codes ORDER BY created_at DESC', []);
  return rows.map(rowToCode);
}

async function dbSaveActivationCode(code) {
  await run(`
    INSERT INTO activation_codes
      (hash, created_at, expires_at, max_uses, used_count, note, last_used_at, revoked, revoked_at, used_records)
    VALUES (?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(hash) DO UPDATE SET
      used_count   = excluded.used_count,
      last_used_at = excluded.last_used_at,
      revoked      = excluded.revoked,
      revoked_at   = excluded.revoked_at,
      used_records = excluded.used_records,
      note         = excluded.note
  `, [
    code.hash,
    code.created_at || null,
    code.expires_at || null,
    code.max_uses ?? 1,
    code.used_count ?? 0,
    code.note || null,
    code.last_used_at || null,
    code.revoked ? 1 : 0,
    code.revoked_at || null,
    JSON.stringify(code.used_records || []),
  ]);
}

async function dbDeleteActivationCode(hash) {
  await run('DELETE FROM activation_codes WHERE hash = ?', [hash]);
}

// ── 导出 ───────────────────────────────────────────────

module.exports = {
  initSQLiteDatabase,
  // users
  dbGetUser,
  dbGetUserByPhone,
  dbGetUserByToken,
  dbSaveUser,
  dbDeleteUser,
  dbListUsers,
  // devices
  dbGetDevice,
  dbGetAllDevices,
  dbUpsertDevice,
  dbGetDevicesByUser,
  dbSetDeviceBanned,
  dbDeleteDevice,
  // sessions
  dbAddSession,
  dbUpdateSessionHeartbeat,
  dbEndSession,
  dbGetDeviceSessions,
  dbGetAllActiveSessions,
  // activation codes
  dbGetActivationCode,
  dbGetAllActivationCodes,
  dbSaveActivationCode,
  dbDeleteActivationCode,
};
