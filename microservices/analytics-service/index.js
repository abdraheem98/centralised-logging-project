'use strict';
const express = require('express');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'analytics-service';
const PORT = process.env.PORT || 3010;

const events = [];

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.post('/events', (req, res) => {
  const { type, userId, data } = req.body;
  if (!type || !userId) {
    logger.warn('Event tracking failed - missing fields', { service: SERVICE });
    return res.status(400).json({ error: 'type and userId required' });
  }
  const event = { type, userId, data, timestamp: new Date().toISOString() };
  events.push(event);
  logger.info('Event tracked', { service: SERVICE, eventType: type, userId });
  res.status(201).json({ message: 'Event recorded', event });
});

app.get('/analytics/summary', (req, res) => {
  const summary = events.reduce((acc, e) => {
    acc[e.type] = (acc[e.type] || 0) + 1;
    return acc;
  }, {});
  logger.info('Analytics summary generated', { service: SERVICE, totalEvents: events.length });
  res.json({ totalEvents: events.length, summary });
});

app.get('/analytics/users/:userId', (req, res) => {
  const userEvents = events.filter(e => e.userId === req.params.userId);
  logger.info('User analytics fetched', { service: SERVICE, userId: req.params.userId, eventCount: userEvents.length });
  res.json(userEvents);
});

// Periodic analytics report log
setInterval(() => {
  const eventTypes = [...new Set(events.map(e => e.type))];
  logger.info('Periodic analytics report', { service: SERVICE, totalEvents: events.length, uniqueEventTypes: eventTypes.length });

  // Simulate high-volume event warning
  if (events.length > 1000) {
    logger.warn('High event volume detected', { service: SERVICE, count: events.length });
  }
}, 11000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
