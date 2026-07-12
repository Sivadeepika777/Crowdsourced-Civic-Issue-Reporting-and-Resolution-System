/**
 * AI Civic Guardian - Backend (Node.js + Express)
 *
 * Run with:
 *   npm install
 *   cp .env.example .env      (then edit JWT_SECRET to something random)
 *   npm start
 *
 * Server listens on http://localhost:8000 by default.
 * Talks to database.js (SQLite) for all persistence.
 */
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { randomUUID: uuidv4 } = require('crypto');

const db = require('./database');

const JWT_SECRET = process.env.JWT_SECRET || 'CHANGE_THIS_TO_A_LONG_RANDOM_SECRET';
const PORT = process.env.PORT || 8000;
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, 'uploads');
const CORS_ORIGINS = process.env.CORS_ORIGINS || '*';

fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// ============================================================================
// CONSTANTS (kept in sync with the frontend's script.js)
// ============================================================================

const CATEGORIES = [
  'Potholes', 'Garbage Dump', 'Water Leakage', 'Sewage Overflow',
  'Broken Streetlight', 'Illegal Dumping', 'Traffic Signal Damage',
  'Road Damage', 'Drainage Blockage', 'Tree Fallen', 'Public Toilet Issues',
  'Stray Animals', 'Flooding', 'Pollution', 'Noise Pollution',
  'Encroachment', 'Park Maintenance', 'Electricity Problems',
  'Drinking Water Problems', 'Road Accident Spot', 'Public Property Damage',
  'Illegal Construction', 'Fire Hazard', 'Other Issues',
];

const SEVERITY_LEVELS = ['Low', 'Medium', 'High', 'Critical'];
const STATUSES = ['Submitted', 'Verified', 'Assigned', 'In Progress', 'Resolved', 'Closed', 'Reopened'];

const DEPARTMENT_MAP = {
  'Potholes': 'Roads Department', 'Road Damage': 'Roads Department',
  'Road Accident Spot': 'Roads Department', 'Garbage Dump': 'Sanitation Department',
  'Illegal Dumping': 'Sanitation Department', 'Water Leakage': 'Water Supply Department',
  'Drinking Water Problems': 'Water Supply Department', 'Sewage Overflow': 'Municipality',
  'Drainage Blockage': 'Municipality', 'Flooding': 'Municipality',
  'Broken Streetlight': 'Electricity Board', 'Electricity Problems': 'Electricity Board',
  'Traffic Signal Damage': 'Police Department', 'Encroachment': 'Police Department',
  'Illegal Construction': 'Corporation', 'Public Toilet Issues': 'Corporation',
  'Park Maintenance': 'Corporation', 'Tree Fallen': 'Forest Department',
  'Fire Hazard': 'Fire Department', 'Stray Animals': 'Municipality',
  'Pollution': 'Municipality', 'Noise Pollution': 'Police Department',
  'Public Property Damage': 'Corporation',
};

function departmentForCategory(category) {
  return DEPARTMENT_MAP[category] || 'Municipality';
}

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_IMAGE_SIZE_BYTES = 8 * 1024 * 1024; // 8 MB

// ============================================================================
// APP SETUP
// ============================================================================

const app = express();

app.use(cors({ origin: CORS_ORIGINS === '*' ? '*' : CORS_ORIGINS.split(',').map((s) => s.trim()) }));
app.use(express.json());
app.use('/uploads', express.static(UPLOAD_DIR));

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, UPLOAD_DIR),
    filename: (req, file, cb) => cb(null, `${uuidv4()}${path.extname(file.originalname) || '.jpg'}`),
  }),
  limits: { fileSize: MAX_IMAGE_SIZE_BYTES, files: 5 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_IMAGE_TYPES.has(file.mimetype)) {
      return cb(new Error(`Unsupported image type: ${file.mimetype}. Use JPEG, PNG, or WebP.`));
    }
    cb(null, true);
  },
});

// ============================================================================
// SERIALIZATION HELPERS (DB row -> API response shape)
// ============================================================================

function serializeUser(row) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    phone: row.phone,
    role: row.role,
    points: row.points,
    created_at: row.created_at,
  };
}

function serializeComplaint(row) {
  const isAnonymous = !!row.is_anonymous;
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    category: row.category,
    severity: row.severity,
    status: row.status,
    latitude: row.latitude,
    longitude: row.longitude,
    address: row.address,
    landmark: row.landmark,
    is_anonymous: isAnonymous,
    contact_number: row.contact_number,
    image_urls: JSON.parse(row.image_urls),
    reported_by: isAnonymous ? null : row.reported_by,
    department: row.department,
    status_history: JSON.parse(row.status_history),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

// ============================================================================
// AUTH HELPERS
// ============================================================================

function createAccessToken(userId) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '24h' });
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ detail: 'Not authenticated' });

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(payload.sub);
    if (!user) return res.status(401).json({ detail: 'User no longer exists' });
    req.user = user;
    next();
  } catch (e) {
    return res.status(401).json({ detail: 'Could not validate credentials' });
  }
}

function requireRole(...allowedRoles) {
  return (req, res, next) => {
    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ detail: 'Not authorized for this action' });
    }
    next();
  };
}

// ============================================================================
// HEALTH
// ============================================================================

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', service: 'ai-civic-guardian-api' });
});

// ============================================================================
// AUTH ROUTES
// ============================================================================

app.post('/api/auth/register', (req, res) => {
  const { name, email, phone, password } = req.body || {};

  if (!name || name.trim().length < 2) return res.status(422).json({ detail: 'Enter a valid name (min 2 characters)' });
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(422).json({ detail: 'Enter a valid email' });
  if (!password || password.length < 6) return res.status(422).json({ detail: 'Password must be at least 6 characters' });

  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (existing) return res.status(400).json({ detail: 'An account with this email already exists' });

  const user = {
    id: uuidv4(),
    name: name.trim(),
    email,
    phone: phone || null,
    password_hash: bcrypt.hashSync(password, 10),
    role: 'citizen',
    points: 0,
    created_at: new Date().toISOString(),
  };

  db.prepare(
    `INSERT INTO users (id, name, email, phone, password_hash, role, points, created_at)
     VALUES (@id, @name, @email, @phone, @password_hash, @role, @points, @created_at)`
  ).run(user);

  res.status(201).json(serializeUser(user));
});

app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) return res.status(422).json({ detail: 'Email and password are required' });

  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ detail: 'Incorrect email or password' });
  }

  res.json({ access_token: createAccessToken(user.id), token_type: 'bearer' });
});

app.get('/api/auth/me', requireAuth, (req, res) => {
  res.json(serializeUser(req.user));
});

// ============================================================================
// COMPLAINT ROUTES
// ============================================================================

app.post('/api/complaints', requireAuth, (req, res) => {
  upload.array('images', 5)(req, res, (err) => {
    if (err) return res.status(400).json({ detail: err.message });

    const {
      title, description, category, severity,
      latitude, longitude, address, landmark,
      is_anonymous, contact_number,
    } = req.body;

    if (!title || title.trim().length < 3) return res.status(422).json({ detail: 'Enter a title (min 3 characters)' });
    if (!description || description.trim().length < 5) return res.status(422).json({ detail: 'Describe the issue (min 5 characters)' });
    if (!CATEGORIES.includes(category)) return res.status(422).json({ detail: 'Invalid category' });
    if (severity && !SEVERITY_LEVELS.includes(severity)) return res.status(422).json({ detail: 'Invalid severity' });
    if (latitude === undefined || longitude === undefined) return res.status(422).json({ detail: 'Location is required' });

    const now = new Date().toISOString();
    const imageUrls = (req.files || []).map((f) => `/uploads/${f.filename}`);
    const isAnonymous = is_anonymous === 'true' || is_anonymous === true;

    const complaint = {
      id: uuidv4(),
      title: title.trim(),
      description: description.trim(),
      category,
      severity: severity || 'Medium',
      status: 'Submitted',
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      address: address || null,
      landmark: landmark || null,
      is_anonymous: isAnonymous ? 1 : 0,
      contact_number: contact_number || null,
      image_urls: JSON.stringify(imageUrls),
      reported_by: req.user.id,
      department: departmentForCategory(category),
      status_history: JSON.stringify([{ status: 'Submitted', note: 'Complaint received', timestamp: now }]),
      created_at: now,
      updated_at: now,
    };

    db.prepare(
      `INSERT INTO complaints (
         id, title, description, category, severity, status, latitude, longitude,
         address, landmark, is_anonymous, contact_number, image_urls, reported_by,
         department, status_history, created_at, updated_at
       ) VALUES (
         @id, @title, @description, @category, @severity, @status, @latitude, @longitude,
         @address, @landmark, @is_anonymous, @contact_number, @image_urls, @reported_by,
         @department, @status_history, @created_at, @updated_at
       )`
    ).run(complaint);

    db.prepare('UPDATE users SET points = points + 10 WHERE id = ?').run(req.user.id);

    res.status(201).json(serializeComplaint(complaint));
  });
});

app.get('/api/complaints', requireAuth, (req, res) => {
  const { category, status, mine_only, limit } = req.query;

  let query = 'SELECT * FROM complaints WHERE 1=1';
  const params = [];

  if (category) {
    query += ' AND category = ?';
    params.push(category);
  }
  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }
  if (mine_only === 'true') {
    query += ' AND reported_by = ?';
    params.push(req.user.id);
  }

  query += ' ORDER BY created_at DESC LIMIT ?';
  params.push(Math.min(parseInt(limit, 10) || 50, 200));

  const rows = db.prepare(query).all(...params);
  res.json(rows.map(serializeComplaint));
});

app.get('/api/complaints/stats/dashboard', requireAuth, (req, res) => {
  const userId = req.user.id;
  const total = db.prepare('SELECT COUNT(*) AS c FROM complaints WHERE reported_by = ?').get(userId).c;
  const resolved = db
    .prepare("SELECT COUNT(*) AS c FROM complaints WHERE reported_by = ? AND status IN ('Resolved', 'Closed')")
    .get(userId).c;
  const pending = db
    .prepare("SELECT COUNT(*) AS c FROM complaints WHERE reported_by = ? AND status IN ('Submitted', 'Verified', 'Assigned')")
    .get(userId).c;
  const inProgress = db
    .prepare("SELECT COUNT(*) AS c FROM complaints WHERE reported_by = ? AND status = 'In Progress'")
    .get(userId).c;

  res.json({
    total_submitted: total,
    resolved,
    pending,
    in_progress: inProgress,
    points: req.user.points,
  });
});

app.get('/api/complaints/:id', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM complaints WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ detail: 'Complaint not found' });
  res.json(serializeComplaint(row));
});

app.patch('/api/complaints/:id/status', requireAuth, requireRole('officer', 'admin'), (req, res) => {
  const { status, resolution_notes } = req.body || {};
  if (!STATUSES.includes(status)) return res.status(422).json({ detail: 'Invalid status' });

  const row = db.prepare('SELECT * FROM complaints WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ detail: 'Complaint not found' });

  const now = new Date().toISOString();
  const history = JSON.parse(row.status_history);
  history.push({ status, note: resolution_notes || null, timestamp: now });

  db.prepare('UPDATE complaints SET status = ?, status_history = ?, updated_at = ? WHERE id = ?').run(
    status,
    JSON.stringify(history),
    now,
    req.params.id
  );

  const updated = db.prepare('SELECT * FROM complaints WHERE id = ?').get(req.params.id);
  res.json(serializeComplaint(updated));
});

// ============================================================================
// ERROR HANDLING
// ============================================================================

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ detail: 'Internal server error' });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`AI Civic Guardian API listening on http://localhost:${PORT}`);
  });
}

module.exports = app;
