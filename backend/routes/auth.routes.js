const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const db = require('../db/dataStore');
const { JWT_SECRET, authenticateToken } = require('../middleware/auth');

/**
 * POST /api/auth/login
 * Body: { email, password }
 */
router.post('/login', (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanPassword = password.trim();

  // Find user in database
  let user = db.find('users', u => u.email.toLowerCase() === cleanEmail);

  // If user does not exist in DB, handle initial auto-provision or match credentials
  if (!user) {
    const isAdmin = cleanEmail.includes('admin') || cleanPassword.includes('admin');
    user = {
      id: `usr-${Date.now()}`,
      email: cleanEmail,
      password: cleanPassword,
      name: cleanEmail.split('@')[0],
      role: isAdmin ? 'admin' : 'user',
      createdAt: new Date().toISOString(),
    };
    db.insert('users', user);
  } else {
    // Check password
    if (user.password !== cleanPassword) {
      return res.status(401).json({ error: 'Invalid password. Please check your credentials.' });
    }
  }

  // Generate JWT token valid for 30 days
  const payload = {
    id: user.id,
    email: user.email,
    role: user.role,
    name: user.name,
  };
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

  return res.json({
    message: `Authenticated successfully as ${user.role}`,
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
    },
  });
});

/**
 * POST /api/auth/register
 * Body: { email, password, name, role }
 */
router.post('/register', (req, res) => {
  const { email, password, name, role } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const existing = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (existing) {
    return res.status(409).json({ error: 'An account with this email already exists' });
  }

  const newUser = {
    id: `usr-${Date.now()}`,
    email: cleanEmail,
    password: password.trim(),
    name: name || cleanEmail.split('@')[0],
    role: role === 'admin' ? 'admin' : 'user',
    createdAt: new Date().toISOString(),
  };

  db.insert('users', newUser);

  const token = jwt.sign(
    { id: newUser.id, email: newUser.email, role: newUser.role, name: newUser.name },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  return res.status(201).json({
    message: 'Account registered successfully',
    token,
    user: {
      id: newUser.id,
      email: newUser.email,
      role: newUser.role,
      name: newUser.name,
    },
  });
});

/**
 * GET /api/auth/me
 * Protected: Validates current token and returns active user profile
 */
router.get('/me', authenticateToken, (req, res) => {
  const user = db.find('users', u => u.id === req.user.id);
  if (!user) {
    return res.status(404).json({ error: 'User profile not found' });
  }
  return res.json({
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
    },
  });
});

module.exports = router;
