'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'payment-service';
const PORT = process.env.PORT || 3003;
const transactions = [];

function simulateGateway(amount) {
  // 10% chance of failure for demo purposes
  if (Math.random() < 0.1) throw new Error('Payment gateway timeout');
  return { gatewayRef: uuidv4(), charged: amount };
}

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.post('/payments', (req, res) => {
  const { orderId, amount, method = 'card' } = req.body;
  if (!orderId || !amount) {
    logger.warn('Payment validation failed', { service: SERVICE });
    return res.status(400).json({ error: 'orderId and amount required' });
  }

  const start = Date.now();
  try {
    const result = simulateGateway(amount);
    const txn = { id: uuidv4(), orderId, amount, method, status: 'SUCCESS', ...result, createdAt: new Date().toISOString() };
    transactions.push(txn);
    const duration = Date.now() - start;
    logger.info('Payment processed', { service: SERVICE, txnId: txn.id, orderId, amount, method, duration_ms: duration });
    res.status(201).json(txn);
  } catch (err) {
    const duration = Date.now() - start;
    logger.error('Payment failed', { service: SERVICE, orderId, amount, error: err.message, duration_ms: duration });
    res.status(502).json({ error: err.message });
  }
});

app.get('/payments/:orderId', (req, res) => {
  const txns = transactions.filter(t => t.orderId === req.params.orderId);
  logger.info('Payment history fetched', { service: SERVICE, orderId: req.params.orderId, count: txns.length });
  res.json(txns);
});

// Simulate periodic reconciliation log
setInterval(() => {
  const total = transactions.reduce((s, t) => s + (t.amount || 0), 0);
  logger.info('Payment reconciliation', { service: SERVICE, totalTransactions: transactions.length, totalAmount: total });
}, 15000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
