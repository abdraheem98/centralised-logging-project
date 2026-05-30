'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'product-service';
const PORT = process.env.PORT || 3006;

const products = [
  { id: 'p1', name: 'Panasonic Mixer Jar 1.5L', category: 'appliance', price: 899, sku: 'SKU-001' },
  { id: 'p2', name: 'Mixer Blade Set Pro', category: 'accessory', price: 349, sku: 'SKU-002' },
  { id: 'p3', name: 'Juicer Attachment', category: 'accessory', price: 499, sku: 'SKU-003' },
];

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.get('/products', (req, res) => {
  const { category } = req.query;
  const result = category ? products.filter(p => p.category === category) : products;
  logger.info('Products listed', { service: SERVICE, count: result.length, filter: category || 'none' });
  res.json(result);
});

app.get('/products/:id', (req, res) => {
  const product = products.find(p => p.id === req.params.id);
  if (!product) {
    logger.warn('Product not found', { service: SERVICE, productId: req.params.id });
    return res.status(404).json({ error: 'Product not found' });
  }
  logger.info('Product fetched', { service: SERVICE, productId: product.id });
  res.json(product);
});

app.post('/products', (req, res) => {
  const { name, category, price, sku } = req.body;
  if (!name || !price) {
    logger.warn('Product validation failed', { service: SERVICE });
    return res.status(400).json({ error: 'name and price required' });
  }
  const product = { id: uuidv4(), name, category, price, sku };
  products.push(product);
  logger.info('Product created', { service: SERVICE, productId: product.id, name });
  res.status(201).json(product);
});

setInterval(() => {
  logger.info('Product catalog sync', { service: SERVICE, totalProducts: products.length });
}, 18000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
