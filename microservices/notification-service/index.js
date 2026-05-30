'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'notification-service';
const PORT = process.env.PORT || 3005;

const notifications = [];
const CHANNELS = ['email', 'sms', 'push'];

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.post('/notify', (req, res) => {
  const { userId, channel, message, subject } = req.body;
  if (!userId || !channel || !message) {
    logger.warn('Notification validation failed', { service: SERVICE });
    return res.status(400).json({ error: 'userId, channel, message required' });
  }
  if (!CHANNELS.includes(channel)) {
    logger.warn('Invalid notification channel', { service: SERVICE, channel });
    return res.status(400).json({ error: `Invalid channel. Use: ${CHANNELS.join(', ')}` });
  }

  // Simulate 5% delivery failure
  const delivered = Math.random() > 0.05;
  const notification = { id: uuidv4(), userId, channel, message, subject, delivered, createdAt: new Date().toISOString() };
  notifications.push(notification);

  if (delivered) {
    logger.info('Notification sent', { service: SERVICE, notifId: notification.id, userId, channel });
  } else {
    logger.error('Notification delivery failed', { service: SERVICE, notifId: notification.id, userId, channel });
  }
  res.status(201).json(notification);
});

app.get('/notifications/:userId', (req, res) => {
  const userNotifs = notifications.filter(n => n.userId === req.params.userId);
  logger.info('Notifications fetched', { service: SERVICE, userId: req.params.userId, count: userNotifs.length });
  res.json(userNotifs);
});

// Simulate scheduled notification dispatch
setInterval(() => {
  logger.info('Scheduled digest dispatch', { service: SERVICE, pending: notifications.filter(n => !n.delivered).length });
}, 20000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
