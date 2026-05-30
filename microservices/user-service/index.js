'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'user-service';
const PORT = process.env.PORT || 3001;

// Simulate in-memory users
const users = [
  { id: 'u1', name: 'Alice Kumar', email: 'alice@demo.com', role: 'admin' },
  { id: 'u2', name: 'Bob Rajan', email: 'bob@demo.com', role: 'customer' },
  { id: 'u3', name: 'Carol Devi', email: 'carol@demo.com', role: 'customer' },
];

app.get('/health', (req, res) => {
  logger.info('Health check', { service: SERVICE });
  res.json({ status: 'ok', service: SERVICE, uptime: process.uptime() });
});

app.get('/users', (req, res) => {
  logger.info('Fetching all users', { service: SERVICE, count: users.length });
  res.json({ users, total: users.length });
});

app.get('/users/:id', (req, res) => {
  const user = users.find(u => u.id === req.params.id);
  if (!user) {
    logger.warn('User not found', { service: SERVICE, userId: req.params.id });
    return res.status(404).json({ error: 'User not found' });
  }
  logger.info('User fetched', { service: SERVICE, userId: user.id });
  res.json(user);
});

app.post('/users', (req, res) => {
  const { name, email, role = 'customer' } = req.body;
  if (!name || !email) {
    logger.warn('Validation failed', { service: SERVICE, reason: 'missing name or email' });
    return res.status(400).json({ error: 'name and email are required' });
  }
  const user = { id: uuidv4(), name, email, role };
  users.push(user);
  logger.info('User created', { service: SERVICE, userId: user.id, email });
  res.status(201).json(user);
});

app.delete('/users/:id', (req, res) => {
  const idx = users.findIndex(u => u.id === req.params.id);
  if (idx === -1) {
    logger.warn('Delete failed - user not found', { service: SERVICE, userId: req.params.id });
    return res.status(404).json({ error: 'User not found' });
  }
  users.splice(idx, 1);
  logger.info('User deleted', { service: SERVICE, userId: req.params.id });
  res.json({ message: 'User deleted' });
});

// Simulate random background activity for demo logs
setInterval(() => {
  const events = ['user_session_started', 'user_profile_viewed', 'password_reset_requested'];
  const event = events[Math.floor(Math.random() * events.length)];
  logger.info(`Background event: ${event}`, { service: SERVICE, userId: users[0].id });
}, 8000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
