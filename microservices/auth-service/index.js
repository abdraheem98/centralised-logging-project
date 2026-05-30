'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'auth-service';
const PORT = process.env.PORT || 3007;

const activeSessions = {};
const failedAttempts = {};

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    logger.warn('Login attempt with missing credentials', { service: SERVICE });
    return res.status(400).json({ error: 'email and password required' });
  }

  // Simulate brute-force detection
  failedAttempts[email] = (failedAttempts[email] || 0);
  if (failedAttempts[email] >= 5) {
    logger.error('Account locked due to failed attempts', { service: SERVICE, email, attempts: failedAttempts[email] });
    return res.status(423).json({ error: 'Account temporarily locked' });
  }

  // Demo: accept any password containing "pass"
  if (!password.includes('pass')) {
    failedAttempts[email]++;
    logger.warn('Failed login attempt', { service: SERVICE, email, failedCount: failedAttempts[email] });
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  failedAttempts[email] = 0;
  const token = uuidv4();
  activeSessions[token] = { email, createdAt: new Date().toISOString() };
  logger.info('User logged in', { service: SERVICE, email });
  res.json({ token, message: 'Login successful' });
});

app.post('/auth/logout', (req, res) => {
  const { token } = req.body;
  if (activeSessions[token]) {
    const { email } = activeSessions[token];
    delete activeSessions[token];
    logger.info('User logged out', { service: SERVICE, email });
    return res.json({ message: 'Logged out' });
  }
  res.status(401).json({ error: 'Invalid token' });
});

app.post('/auth/verify', (req, res) => {
  const { token } = req.body;
  if (!activeSessions[token]) {
    logger.warn('Token verification failed', { service: SERVICE });
    return res.status(401).json({ valid: false });
  }
  res.json({ valid: true, session: activeSessions[token] });
});

// Session audit log
setInterval(() => {
  logger.info('Active session count', { service: SERVICE, sessions: Object.keys(activeSessions).length });
}, 14000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
