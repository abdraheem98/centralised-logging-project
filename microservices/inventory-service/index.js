'use strict';
const express = require('express');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'inventory-service';
const PORT = process.env.PORT || 3004;

const inventory = {
  'SKU-001': { name: 'Widget A', quantity: 100, reorderLevel: 20 },
  'SKU-002': { name: 'Widget B', quantity: 15,  reorderLevel: 20 },
  'SKU-003': { name: 'Gadget X', quantity: 50,  reorderLevel: 10 },
  'SKU-004': { name: 'Gadget Y', quantity: 0,   reorderLevel: 5 },
};

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.get('/inventory', (req, res) => {
  logger.info('Inventory listed', { service: SERVICE, skuCount: Object.keys(inventory).length });
  res.json(inventory);
});

app.get('/inventory/:sku', (req, res) => {
  const item = inventory[req.params.sku];
  if (!item) return res.status(404).json({ error: 'SKU not found' });
  logger.info('Inventory item fetched', { service: SERVICE, sku: req.params.sku, quantity: item.quantity });
  res.json({ sku: req.params.sku, ...item });
});

app.patch('/inventory/:sku/reserve', (req, res) => {
  const { quantity } = req.body;
  const item = inventory[req.params.sku];
  if (!item) return res.status(404).json({ error: 'SKU not found' });

  if (item.quantity < quantity) {
    logger.warn('Insufficient inventory', { service: SERVICE, sku: req.params.sku, requested: quantity, available: item.quantity });
    return res.status(409).json({ error: 'Insufficient stock' });
  }
  item.quantity -= quantity;
  logger.info('Inventory reserved', { service: SERVICE, sku: req.params.sku, reserved: quantity, remaining: item.quantity });

  if (item.quantity <= item.reorderLevel) {
    logger.warn('Stock below reorder level', { service: SERVICE, sku: req.params.sku, quantity: item.quantity, reorderLevel: item.reorderLevel });
  }
  res.json({ sku: req.params.sku, ...item });
});

// Periodic stock-level audit log
setInterval(() => {
  Object.entries(inventory).forEach(([sku, item]) => {
    if (item.quantity === 0) {
      logger.error('Out of stock', { service: SERVICE, sku, name: item.name });
    }
  });
}, 12000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
