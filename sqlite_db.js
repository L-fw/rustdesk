const path = require('path');
const sqlite3 = require('sqlite3').verbose();

function initSQLiteDatabase(baseDir) {
  const dbPath = path.join(baseDir, 'server.db');
  const db = new sqlite3.Database(dbPath);

  db.serialize(() => {
    db.run('PRAGMA journal_mode=WAL');
    db.run(`
      CREATE TABLE IF NOT EXISTS users (
        username TEXT PRIMARY KEY,
        password_hash TEXT NOT NULL,
        phone TEXT UNIQUE NOT NULL,
        token TEXT,
        activation_code_hash TEXT,
        activated INTEGER DEFAULT 1,
        created_at TEXT,
        last_login TEXT,
        password_updated_at TEXT
      )
    `);
    db.run(`
      CREATE TABLE IF NOT EXISTS activation_codes (
        hash TEXT PRIMARY KEY,
        created_at TEXT,
        expires_at TEXT,
        max_uses INTEGER DEFAULT 1,
        used_count INTEGER DEFAULT 0,
        note TEXT,
        last_used_at TEXT
      )
    `);
    db.run(`
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        first_seen TEXT,
        last_seen TEXT,
        ip TEXT,
        banned INTEGER DEFAULT 0,
        username TEXT,
        phone TEXT,
        app_version TEXT,
        password TEXT
      )
    `);
    db.run(`
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        peer_id TEXT,
        start_time TEXT,
        last_heartbeat TEXT,
        ended INTEGER DEFAULT 0,
        end_time TEXT
      )
    `);
    db.run(`
      CREATE TABLE IF NOT EXISTS version_config (
        platform TEXT PRIMARY KEY,
        latest_version TEXT,
        min_required TEXT,
        force_update INTEGER DEFAULT 0,
        download_url TEXT,
        update_log TEXT,
        release_url TEXT
      )
    `);
  });

  db.close((err) => {
    if (err) {
      console.error(`[DB] SQLite close failed: ${err.message}`);
      return;
    }
    console.log(`[DB] SQLite ready: ${dbPath}`);
  });
}

module.exports = { initSQLiteDatabase };
