/**
 * AI Civic Guardian - Database (SQLite)
 *
 * Uses Node.js's BUILT-IN `node:sqlite` module (available from Node 22.5+),
 * so there is no native addon to compile and no extra package to install
 * for the database itself - it ships with Node. This is a real, persistent,
 * file-based SQL database (not localStorage, not in-memory).
 *
 * The .db file is created automatically on first run in this same folder.
 * Arrays (image_urls, status_history) are stored as JSON text columns since
 * SQLite has no native array/JSON type.
 *
 * Note: node:sqlite is still marked "experimental" by Node.js. It is fully
 * functional (used here with real read/write/query workloads), but if your
 * Node version is older than 22.5, see the README for the drop-in
 * better-sqlite3 alternative.
 */
const { DatabaseSync } = require('node:sqlite');
const path = require('path');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'civic_guardian.db');

const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone TEXT,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'citizen',
    points INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS complaints (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    severity TEXT NOT NULL,
    status TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    address TEXT,
    landmark TEXT,
    is_anonymous INTEGER NOT NULL DEFAULT 0,
    contact_number TEXT,
    image_urls TEXT NOT NULL DEFAULT '[]',
    reported_by TEXT NOT NULL,
    department TEXT NOT NULL,
    status_history TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (reported_by) REFERENCES users(id)
  );
`);

db.exec('CREATE INDEX IF NOT EXISTS idx_complaints_reported_by ON complaints(reported_by);');
db.exec('CREATE INDEX IF NOT EXISTS idx_complaints_category ON complaints(category);');
db.exec('CREATE INDEX IF NOT EXISTS idx_complaints_status ON complaints(status);');

/**
 * node:sqlite's .all()/.get() return rows as null-prototype objects, and its
 * .run() result shape differs slightly from better-sqlite3's. The wrapper
 * below normalizes access to the same familiar db.prepare(sql).get/all/run()
 * calls used throughout server.js - this also makes it a true drop-in swap
 * for better-sqlite3 later if you ever need to (see README).
 */
const originalPrepare = db.prepare.bind(db);
db.prepare = (sql) => {
  const stmt = originalPrepare(sql);
  return {
    get: (...args) => stmt.get(...args),
    all: (...args) => stmt.all(...args),
    run: (...args) => stmt.run(...args),
  };
};

module.exports = db;
