'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'order-service';
const PORT = process.env.PORT || 3002;

const orders = [];
const STATUS = ['PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED'];

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.get('/orders', (req, res) => {
  logger.info('Listing orders', { service: SERVICE, count: orders.length });
  res.json({ orders, total: orders.length });
});

app.post('/orders', (req, res) => {
  const { userId, items, totalAmount } = req.body;
  if (!userId || !items || !totalAmount) {
    logger.warn('Order creation validation failed', { service: SERVICE });
    return res.status(400).json({ error: 'userId, items, totalAmount required' });
  }
  const order = {
    id: uuidv4(),
    userId,
    items,
    totalAmount,
    status: 'PENDING',
    createdAt: new Date().toISOString(),
  };
  orders.push(order);
  logger.info('Order created', {
    service: SERVICE,
    orderId: order.id,
    userId,
    totalAmount,
    itemCount: items.length,
  });
  res.status(201).json(order);
});

app.patch('/orders/:id/status', (req, res) => {
  const order = orders.find(o => o.id === req.params.id);
  if (!order) return res.status(404).json({ error: 'Order not found' });

  const { status } = req.body;
  if (!STATUS.includes(status)) {
    logger.warn('Invalid order status', { service: SERVICE, status });
    return res.status(400).json({ error: 'Invalid status' });
  }
  const oldStatus = order.status;
  order.status = status;
  logger.info('Order status updated', { service: SERVICE, orderId: order.id, from: oldStatus, to: status });
  res.json(order);
});

// Simulate order processing background logs
setInterval(() => {
  if (orders.length > 0) {
    const o = orders[Math.floor(Math.random() * orders.length)];
    logger.info('Order processing heartbeat', { service: SERVICE, orderId: o.id, status: o.status });
  } else {
    logger.info('No orders to process', { service: SERVICE });
  }
}, 10000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
