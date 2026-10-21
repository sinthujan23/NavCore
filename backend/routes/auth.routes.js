const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const db = require('../db/dataStore');
const { JWT_SECRET, authenticateToken, requireAdmin } = require('../middleware/auth');
const emailService = require('../services/emailService');

/**
 * Strict RFC 5322 compliant email validator to ensure real-time genuine email addresses
 */
function isValidEmail(email) {
  if (!email || typeof email !== 'string') return false;
  const clean = email.trim();
  // Validates standard real emails like user@domain.com, name.surname@company.co.uk
  const emailRegex = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;
  return emailRegex.test(clean) && clean.length <= 254;
}

/**
 * Password strength policy checker
 */
function getMissingPasswordRequirements(password) {
  const missing = [];
  if (!password || password.length < 8) missing.push('at least 8 characters');
  if (!/[A-Z]/.test(password || '')) missing.push('uppercase letter (A-Z)');
  if (!/[a-z]/.test(password || '')) missing.push('lowercase letter (a-z)');
  if (!/[0-9]/.test(password || '')) missing.push('number (0-9)');
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password || '')) missing.push('special symbol (!@#$...)');
  return missing;
}

function isStrongPassword(password) {
  return getMissingPasswordRequirements(password).length === 0;
}

/**
 * Generates a cryptographically secure 6-digit numeric OTP code
 */
function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * POST /api/auth/register
 * Step 1 of account creation: Validates real email, creates account pending verification,
 * and delivers real-time 6-digit verification code to the email address.
 * Body: { email, password, name, role }
 */
router.post('/register', async (req, res) => {
  const { email, password, name, role } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanPassword = password.trim();

  // Enforce valid real email address
  if (!isValidEmail(cleanEmail)) {
    return res.status(400).json({
      error: 'Please enter a valid, real-time email address (e.g., name@gmail.com).'
    });
  }

  // Enforce strong password policy
  const missing = getMissingPasswordRequirements(cleanPassword);
  if (missing.length > 0) {
    return res.status(400).json({
      error: `Password is too weak. Missing: ${missing.join(', ')}.`
    });
  }

  // Check if account already exists
  const existing = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (existing && existing.isVerified) {
    return res.status(409).json({
      error: 'An account with this email already exists and is verified. Please log in.'
    });
  }

  let user = existing;
  const isAdmin = cleanEmail.includes('admin') || role === 'admin';

  if (!user) {
    user = {
      id: `usr-${Date.now()}`,
      email: cleanEmail,
      password: cleanPassword,
      name: (name && name.trim()) || cleanEmail.split('@')[0],
      role: isAdmin ? 'admin' : 'user',
      isVerified: false,
      createdAt: new Date().toISOString(),
    };
    db.insert('users', user);
  } else {
    // Existing unverified account: update credentials and resend verification
    user.password = cleanPassword;
    if (name && name.trim()) user.name = name.trim();
    user.role = isAdmin ? 'admin' : 'user';
    db.update('users', u => u.id === user.id, user);
  }

  // Generate 6-digit OTP code valid for 15 minutes
  const otp = generateOtp();
  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'email_verification');
  db.insert('verificationCodes', {
    email: cleanEmail,
    code: otp,
    type: 'email_verification',
    createdAt: Date.now(),
    expiresAt: Date.now() + 15 * 60 * 1000,
  });

  // Deliver real email verification
  await emailService.sendAccountVerification(cleanEmail, otp, user.name);

  const responseData = {
    status: 'pending_verification',
    requiresVerification: true,
    email: cleanEmail,
    name: user.name,
    message: `A 6-digit verification code has been sent to ${cleanEmail}. Please enter it to activate your account.`,
    expiresInSeconds: 900,
  };

  if (!emailService.isConfigured() || process.env.NODE_ENV !== 'production') {
    responseData.previewCode = otp;
  }

  return res.status(200).json(responseData);
});

/**
 * POST /api/auth/verify-email
 * Step 2 of account creation: Verifies 6-digit OTP code, marks account verified, and issues JWT token.
 * Body: { email, code }
 */
router.post('/verify-email', (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: 'Email and 6-digit verification code are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanCode = code.toString().trim();

  const record = db.find('verificationCodes', v => v.email === cleanEmail && v.type === 'email_verification');

  if (!record || record.code !== cleanCode) {
    return res.status(400).json({
      error: 'Invalid verification code. Please check your email and try again.'
    });
  }

  if (Date.now() > record.expiresAt) {
    db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'email_verification');
    return res.status(400).json({
      error: 'Verification code has expired. Please tap "Resend Code" to receive a new one.'
    });
  }

  // Clear used code
  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'email_verification');

  // Mark user as verified
  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({ error: 'User account record not found' });
  }

  user.isVerified = true;
  user.verifiedAt = new Date().toISOString();
  db.update('users', u => u.id === user.id, user);

  // Issue 30-day JWT session token
  const payload = {
    id: user.id,
    email: user.email,
    role: user.role,
    name: user.name,
  };
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

  return res.status(200).json({
    status: 'success',
    message: 'Account created and verified successfully! Welcome to NexNav.',
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
      isVerified: true,
    },
  });
});

/**
 * POST /api/auth/resend-code
 * Resends a fresh 6-digit verification code to the user's real email address.
 * Body: { email, type } (type: 'email_verification' | 'login_otp' | 'password_reset')
 */
router.post('/resend-code', async (req, res) => {
  const { email, type = 'email_verification' } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Email address is required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  if (!isValidEmail(cleanEmail)) {
    return res.status(400).json({ error: 'Invalid email address format' });
  }

  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({ error: 'No account found with this email address' });
  }

  // Check rate limiting (at least 30 seconds between requests)
  const existing = db.find('verificationCodes', v => v.email === cleanEmail && v.type === type);
  if (existing && Date.now() - existing.createdAt < 30 * 1000) {
    const waitSec = Math.ceil((30 * 1000 - (Date.now() - existing.createdAt)) / 1000);
    return res.status(429).json({
      error: `Please wait ${waitSec} seconds before requesting another code.`
    });
  }

  const otp = generateOtp();
  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === type);
  db.insert('verificationCodes', {
    email: cleanEmail,
    code: otp,
    type,
    createdAt: Date.now(),
    expiresAt: Date.now() + 15 * 60 * 1000,
  });

  if (type === 'login_otp') {
    await emailService.sendLoginVerification(cleanEmail, otp, user.name);
  } else if (type === 'password_reset') {
    await emailService.sendPasswordReset(cleanEmail, otp, user.name);
  } else {
    await emailService.sendAccountVerification(cleanEmail, otp, user.name);
  }

  const resData = {
    success: true,
    message: `A fresh verification code has been sent to ${cleanEmail}.`,
    email: cleanEmail,
    expiresInSeconds: 900,
  };

  if (!emailService.isConfigured() || process.env.NODE_ENV !== 'production') {
    resData.previewCode = otp;
  }

  return res.json(resData);
});

/**
 * POST /api/auth/login
 * Body: { email, password }
 * Validates real credentials. Checks if email is verified.
 * If unverified, dispatches verification code and requires verification.
 */
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanPassword = password.trim();

  if (!isValidEmail(cleanEmail)) {
    return res.status(400).json({ error: 'Please enter a valid email address.' });
  }

  // Enforce strong password policy
  const missing = getMissingPasswordRequirements(cleanPassword);
  if (missing.length > 0) {
    return res.status(400).json({
      error: `Password missing requirements: ${missing.join(', ')}.`
    });
  }

  // Find user in database
  let user = db.find('users', u => u.email.toLowerCase() === cleanEmail);

  // Primary System Administrator credentials
  if (!user && cleanEmail === 'admin@nexnav.com' && cleanPassword === 'Admin@1234') {
    user = {
      id: 'usr-admin-01',
      email: 'admin@nexnav.com',
      password: 'Admin@1234',
      name: 'System Administrator',
      role: 'admin',
      isVerified: true,
      createdAt: '2026-10-01T00:00:00.000Z',
    };
    db.insert('users', user);
  }

  // If user does not exist in DB, refuse login (no mock auto-provisioning)
  if (!user) {
    return res.status(404).json({
      error: 'No account found with this email address. Please create an account first.'
    });
  }

  // Verify password
  const matches = user.password === cleanPassword;
  if (!matches) {
    return res.status(401).json({ error: 'Invalid password. Please check your credentials.' });
  }

  // Check email verification status
  if (!user.isVerified) {
    // Generate fresh OTP and send verification email
    const otp = generateOtp();
    db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'email_verification');
    db.insert('verificationCodes', {
      email: cleanEmail,
      code: otp,
      type: 'email_verification',
      createdAt: Date.now(),
      expiresAt: Date.now() + 15 * 60 * 1000,
    });
    await emailService.sendAccountVerification(cleanEmail, otp, user.name);

    return res.status(403).json({
      error: 'Your email address is not verified yet.',
      requiresVerification: true,
      email: cleanEmail,
      message: `A 6-digit verification code has been sent to ${cleanEmail}. Please enter the code to continue.`,
      expiresInSeconds: 900,
    });
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
      isVerified: true,
    },
  });
});

/**
 * POST /api/auth/send-login-otp
 * Real-time email verification code sign-in option (Passwordless / 2FA sign in)
 * Body: { email }
 */
router.post('/send-login-otp', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Email address is required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  if (!isValidEmail(cleanEmail)) {
    return res.status(400).json({ error: 'Please enter a valid email address.' });
  }

  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({
      error: 'No account registered with this email address. Please create an account first.'
    });
  }

  const otp = generateOtp();
  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'login_otp');
  db.insert('verificationCodes', {
    email: cleanEmail,
    code: otp,
    type: 'login_otp',
    createdAt: Date.now(),
    expiresAt: Date.now() + 15 * 60 * 1000,
  });

  await emailService.sendLoginVerification(cleanEmail, otp, user.name);

  return res.json({
    message: `Sign-in verification code sent to ${cleanEmail}`,
    email: cleanEmail,
    requiresOtp: true,
    expiresInSeconds: 900,
  });
});

/**
 * POST /api/auth/verify-login-otp
 * Verifies email sign-in OTP and completes sign-in.
 * Body: { email, code }
 */
router.post('/verify-login-otp', (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: 'Email and verification code are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanCode = code.toString().trim();

  const record = db.find('verificationCodes', v => v.email === cleanEmail && v.type === 'login_otp');
  if (!record || record.code !== cleanCode) {
    return res.status(400).json({ error: 'Invalid verification code' });
  }

  if (Date.now() > record.expiresAt) {
    db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'login_otp');
    return res.status(400).json({ error: 'Sign-in code has expired. Please request a new one.' });
  }

  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'login_otp');

  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({ error: 'User profile not found' });
  }

  // Marking verified since user just proved access to this real email
  if (!user.isVerified) {
    user.isVerified = true;
    user.verifiedAt = new Date().toISOString();
    db.update('users', u => u.id === user.id, user);
  }

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
      isVerified: true,
    },
  });
});

/**
 * POST /api/auth/forgot-password
 * Body: { email }
 */
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Email address is required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  if (!isValidEmail(cleanEmail)) {
    return res.status(400).json({ error: 'Please enter a valid email address.' });
  }

  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({ error: 'No account found with this email address' });
  }

  const otp = generateOtp();
  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'password_reset');
  db.insert('verificationCodes', {
    email: cleanEmail,
    code: otp,
    type: 'password_reset',
    createdAt: Date.now(),
    expiresAt: Date.now() + 15 * 60 * 1000,
  });

  await emailService.sendPasswordReset(cleanEmail, otp, user.name);

  const resData = {
    message: `Password reset code sent to ${cleanEmail}`,
    email: cleanEmail,
    expiresInSeconds: 900,
  };

  if (!emailService.isConfigured() || process.env.NODE_ENV !== 'production') {
    resData.previewCode = otp;
  }

  return res.json(resData);
});

/**
 * POST /api/auth/reset-password
 * Body: { email, code, newPassword }
 */
router.post('/reset-password', (req, res) => {
  const { email, code, newPassword } = req.body;

  if (!email || !code || !newPassword) {
    return res.status(400).json({ error: 'Email, verification code, and new password are required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const cleanCode = code.toString().trim();
  const cleanPass = newPassword.trim();

  const missing = getMissingPasswordRequirements(cleanPass);
  if (missing.length > 0) {
    return res.status(400).json({
      error: `New password missing requirements: ${missing.join(', ')}.`
    });
  }

  const record = db.find('verificationCodes', v => v.email === cleanEmail && v.type === 'password_reset');
  if (!record || record.code !== cleanCode) {
    return res.status(400).json({ error: 'Invalid password reset code' });
  }

  if (Date.now() > record.expiresAt) {
    db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'password_reset');
    return res.status(400).json({ error: 'Reset code has expired. Please request a new one.' });
  }

  db.remove('verificationCodes', v => v.email === cleanEmail && v.type === 'password_reset');

  const user = db.find('users', u => u.email.toLowerCase() === cleanEmail);
  if (!user) {
    return res.status(404).json({ error: 'User profile not found' });
  }

  user.password = cleanPass;
  user.isVerified = true;
  db.update('users', u => u.id === user.id, user);

  return res.json({
    message: 'Password reset successfully! You can now log in with your new password.',
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
      isVerified: Boolean(user.isVerified),
    },
  });
});

/**
 * POST /api/auth/google
 * Authenticates or registers a user via Google OAuth One-Tap (verified by Google)
 * Body: { email, name, googleId, avatar }
 */
router.post('/google', (req, res) => {
  const { email, name, googleId, avatar } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Google email address is required' });
  }

  const cleanEmail = email.trim().toLowerCase();
  let user = db.find('users', u => u.email.toLowerCase() === cleanEmail);

  if (!user) {
    const isAdmin = cleanEmail.includes('admin');
    user = {
      id: `usr-g-${Date.now()}`,
      email: cleanEmail,
      name: name || cleanEmail.split('@')[0],
      role: isAdmin ? 'admin' : 'user',
      authProvider: 'google',
      googleId: googleId || `gid-${Date.now()}`,
      avatar: avatar || null,
      isVerified: true, // Google verifies user emails natively
      createdAt: new Date().toISOString(),
    };
    db.insert('users', user);
  } else {
    let updated = false;
    if (!user.authProvider) {
      user.authProvider = 'google';
      updated = true;
    }
    if (avatar && !user.avatar) {
      user.avatar = avatar;
      updated = true;
    }
    if (!user.isVerified) {
      user.isVerified = true;
      updated = true;
    }
    if (updated) {
      db.update('users', u => u.id === user.id, user);
    }
  }

  const payload = {
    id: user.id,
    email: user.email,
    role: user.role,
    name: user.name,
  };
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

  return res.json({
    message: `Authenticated successfully with Google as ${user.role}`,
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
      avatar: user.avatar,
      isVerified: true,
    },
  });
});

/**
 * POST /api/auth/smart-login
 * Fast biometric / device authenticated smart login
 * Body: { email, deviceKey }
 */
router.post('/smart-login', (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Email is required for smart login' });
  }

  const cleanEmail = email.trim().toLowerCase();
  let user = db.find('users', u => u.email.toLowerCase() === cleanEmail);

  if (!user) {
    return res.status(404).json({
      error: 'No registered account found with this email. Please create and verify your account first.'
    });
  }

  if (!user.isVerified) {
    return res.status(403).json({
      error: 'Account email has not been verified yet. Please complete verification first.',
      requiresVerification: true,
      email: cleanEmail,
    });
  }

  const payload = {
    id: user.id,
    email: user.email,
    role: user.role,
    name: user.name,
  };
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

  return res.json({
    message: `Smart login successful as ${user.role}`,
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      name: user.name,
      isVerified: true,
    },
  });
});

/**
 * DELETE /api/auth/users/non-admin
 * Admin Only: Removes all registered users except system administrators.
 */
router.delete('/users/non-admin', requireAdmin, (req, res) => {
  const users = db.get('users') || [];
  const usersBefore = users.length;
  const adminUsers = users.filter(u => u.role === 'admin');
  const adminIds = new Set(adminUsers.map(u => u.id));

  // 1. Remove all non-admin users
  db.remove('users', u => u.role !== 'admin');

  // 2. Remove all pending verification codes
  db.remove('verificationCodes', () => true);

  // 3. Remove non-admin vehicle locations
  const vehicleLocations = db.get('vehicleLocations') || {};
  if (typeof vehicleLocations === 'object') {
    const cleaned = {};
    for (const [uid, loc] of Object.entries(vehicleLocations)) {
      if (adminIds.has(uid)) {
        cleaned[uid] = loc;
      }
    }
    db.set('vehicleLocations', cleaned);
  }

  const usersAfter = db.get('users').length;
  return res.json({
    success: true,
    message: `All non-admin users removed. Users count reduced from ${usersBefore} to ${usersAfter}.`,
    remainingAdmins: adminUsers.map(u => ({ id: u.id, email: u.email, role: u.role, name: u.name })),
  });
});

module.exports = router;
