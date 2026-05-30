'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('../shared/logger');
const { correlationId, requestLogger, errorHandler } = require('../shared/middleware');

const app = express();
app.use(express.json());
app.use(correlationId);
app.use(requestLogger);

const SERVICE = 'shipping-service';
const PORT = process.env.PORT || 3009;

const shipments = [];
const CARRIERS = ['BlueDart', 'Delhivery', 'DTDC', 'FedEx', 'India Post'];
const STATES = ['LABEL_CREATED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED'];

app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));

app.post('/shipments', (req, res) => {
  const { orderId, address } = req.body;
  if (!orderId || !address) {
    logger.warn('Shipment creation failed - missing fields', { service: SERVICE });
    return res.status(400).json({ error: 'orderId and address required' });
  }
  const carrier = CARRIERS[Math.floor(Math.random() * CARRIERS.length)];
  const shipment = {
    id: uuidv4(),
    orderId,
    address,
    carrier,
    trackingNumber: `TRK${Date.now()}`,
    status: 'LABEL_CREATED',
    estimatedDelivery: new Date(Date.now() + 3 * 86400000).toISOString(),
    createdAt: new Date().toISOString(),
  };
  shipments.push(shipment);
  logger.info('Shipment created', { service: SERVICE, shipmentId: shipment.id, orderId, carrier, tracking: shipment.trackingNumber });
  res.status(201).json(shipment);
});

app.get('/shipments/:trackingNumber', (req, res) => {
  const s = shipments.find(s => s.trackingNumber === req.params.trackingNumber);
  if (!s) {
    logger.warn('Tracking number not found', { service: SERVICE, tracking: req.params.trackingNumber });
    return res.status(404).json({ error: 'Shipment not found' });
  }
  logger.info('Shipment tracked', { service: SERVICE, tracking: s.trackingNumber, status: s.status });
  res.json(s);
});

// Simulate shipment status progression
setInterval(() => {
  shipments.forEach(s => {
    const idx = STATES.indexOf(s.status);
    if (idx < STATES.length - 1 && Math.random() > 0.7) {
      s.status = STATES[idx + 1];
      logger.info('Shipment status updated', { service: SERVICE, shipmentId: s.id, newStatus: s.status, carrier: s.carrier });
    }
  });
}, 9000);

app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} running on port ${PORT}`, { service: SERVICE }));
