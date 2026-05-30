'use strict';
const express = require('express');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'cart-service';
const PORT = process.env.PORT || 3008;

const carts = {};  // { userId: [{ productId, quantity, price }] }

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.get('/cart/:userId', (req, res) => {
  const cart = carts[req.params.userId] || [];
  const total = cart.reduce((s, i) => s + i.price * i.quantity, 0);
  logger.info('Cart fetched', { service: SERVICE, userId: req.params.userId, items: cart.length, total });
  res.json({ userId: req.params.userId, items: cart, total });
});

app.post('/cart/:userId/add', (req, res) => {
  const { productId, quantity, price } = req.body;
  if (!productId || !quantity || !price) {
    logger.warn('Cart add validation failed', { service: SERVICE });
    return res.status(400).json({ error: 'productId, quantity, price required' });
  }
  if (!carts[req.params.userId]) carts[req.params.userId] = [];
  const existing = carts[req.params.userId].find(i => i.productId === productId);
  if (existing) {
    existing.quantity += quantity;
  } else {
    carts[req.params.userId].push({ productId, quantity, price });
  }
  logger.info('Item added to cart', { service: SERVICE, userId: req.params.userId, productId, quantity });
  res.json(carts[req.params.userId]);
});

app.delete('/cart/:userId/remove/:productId', (req, res) => {
  const cart = carts[req.params.userId] || [];
  carts[req.params.userId] = cart.filter(i => i.productId !== req.params.productId);
  logger.info('Item removed from cart', { service: SERVICE, userId: req.params.userId, productId: req.params.productId });
  res.json(carts[req.params.userId]);
});

app.delete('/cart/:userId', (req, res) => {
  carts[req.params.userId] = [];
  logger.info('Cart cleared', { service: SERVICE, userId: req.params.userId });
  res.json({ message: 'Cart cleared' });
});

setInterval(() => {
  const activeCarts = Object.keys(carts).length;
  logger.info('Active carts summary', { service: SERVICE, activeCarts });
}, 16000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
