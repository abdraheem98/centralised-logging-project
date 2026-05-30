#!/bin/bash
# =============================================================================
# Centralized Logging - Complete Auto Setup Script
# Run this on a fresh EC2 Ubuntu 22.04 instance
# Usage: bash setup.sh
# =============================================================================

set -e  # Exit on any error

# ── Colors for output ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BLUE}"
echo "============================================================"
echo "   Centralized Logging - Full Auto Setup"
echo "   ELK Stack + 10 Microservices + AWS CloudWatch"
echo "   EC2 Ubuntu 22.04"
echo "============================================================"
echo -e "${NC}"

# ── Get Public IP ─────────────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ifconfig.me)
echo -e "${CYAN}Your EC2 Public IP: ${PUBLIC_IP}${NC}"
echo ""

# =============================================================================
# STEP 1 — System Update & Basic Tools
# =============================================================================
echo -e "${YELLOW}[1/7] Updating system and installing basic tools...${NC}"
sudo apt-get update -y
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    unzip \
    git \
    wget \
    lsb-release \
    net-tools \
    htop \
    jq
echo -e "${GREEN}✅ System updated${NC}"

# =============================================================================
# STEP 2 — Install Docker & Docker Compose
# =============================================================================
echo ""
echo -e "${YELLOW}[2/7] Installing Docker...${NC}"

# Remove old versions if any
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add ubuntu user to docker group (no sudo needed)
sudo usermod -aG docker ubuntu

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Allow current session to use docker without sudo
sudo chmod 666 /var/run/docker.sock

echo -e "${GREEN}✅ Docker installed: $(docker --version)${NC}"
echo -e "${GREEN}✅ Docker Compose: $(docker compose version)${NC}"

# =============================================================================
# STEP 3 — Install Node.js 18
# =============================================================================
echo ""
echo -e "${YELLOW}[3/7] Installing Node.js 18...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
echo -e "${GREEN}✅ Node.js: $(node --version)${NC}"
echo -e "${GREEN}✅ npm: $(npm --version)${NC}"

# =============================================================================
# STEP 4 — System Tuning for Elasticsearch
# =============================================================================
echo ""
echo -e "${YELLOW}[4/7] Tuning system settings for Elasticsearch...${NC}"

# Elasticsearch requires this to be at least 262144
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null

# Increase file descriptor limits
echo "ubuntu soft nofile 65536" | sudo tee -a /etc/security/limits.conf > /dev/null
echo "ubuntu hard nofile 65536" | sudo tee -a /etc/security/limits.conf > /dev/null

echo -e "${GREEN}✅ vm.max_map_count = $(cat /proc/sys/vm/max_map_count)${NC}"

# =============================================================================
# STEP 5 — Create Project Structure & Config Files
# =============================================================================
echo ""
echo -e "${YELLOW}[5/7] Creating project files...${NC}"

mkdir -p ~/centralized-logging/elk-stack/logstash/{pipeline,config}
mkdir -p ~/centralized-logging/microservices/shared
mkdir -p ~/centralized-logging/microservices/{user-service,order-service,payment-service,inventory-service,notification-service,product-service,auth-service,cart-service,shipping-service,analytics-service}
mkdir -p ~/centralized-logging/scripts

cd ~/centralized-logging

# ── Docker Compose ────────────────────────────────────────────────────────────
cat > elk-stack/docker-compose.yml << 'COMPOSE'
version: '3.8'

networks:
  logging-net:
    driver: bridge

volumes:
  elasticsearch-data:

services:

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1g -Xmx1g
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    networks:
      - logging-net
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10

  logstash:
    image: docker.elastic.co/logstash/logstash:8.12.0
    container_name: logstash
    ports:
      - "5000:5000"
      - "5044:5044"
      - "9600:9600"
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - logging-net

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - xpack.security.enabled=false
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - logging-net

  user-service:
    image: node:18-alpine
    container_name: user-service
    working_dir: /app
    volumes:
      - ../microservices/user-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3001:3001"
    environment:
      - SERVICE_NAME=user-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3001
    depends_on:
      - logstash
    networks:
      - logging-net

  order-service:
    image: node:18-alpine
    container_name: order-service
    working_dir: /app
    volumes:
      - ../microservices/order-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3002:3002"
    environment:
      - SERVICE_NAME=order-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3002
    depends_on:
      - logstash
    networks:
      - logging-net

  payment-service:
    image: node:18-alpine
    container_name: payment-service
    working_dir: /app
    volumes:
      - ../microservices/payment-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3003:3003"
    environment:
      - SERVICE_NAME=payment-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3003
    depends_on:
      - logstash
    networks:
      - logging-net

  inventory-service:
    image: node:18-alpine
    container_name: inventory-service
    working_dir: /app
    volumes:
      - ../microservices/inventory-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3004:3004"
    environment:
      - SERVICE_NAME=inventory-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3004
    depends_on:
      - logstash
    networks:
      - logging-net

  notification-service:
    image: node:18-alpine
    container_name: notification-service
    working_dir: /app
    volumes:
      - ../microservices/notification-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3005:3005"
    environment:
      - SERVICE_NAME=notification-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3005
    depends_on:
      - logstash
    networks:
      - logging-net

  product-service:
    image: node:18-alpine
    container_name: product-service
    working_dir: /app
    volumes:
      - ../microservices/product-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3006:3006"
    environment:
      - SERVICE_NAME=product-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3006
    depends_on:
      - logstash
    networks:
      - logging-net

  auth-service:
    image: node:18-alpine
    container_name: auth-service
    working_dir: /app
    volumes:
      - ../microservices/auth-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3007:3007"
    environment:
      - SERVICE_NAME=auth-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3007
    depends_on:
      - logstash
    networks:
      - logging-net

  cart-service:
    image: node:18-alpine
    container_name: cart-service
    working_dir: /app
    volumes:
      - ../microservices/cart-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3008:3008"
    environment:
      - SERVICE_NAME=cart-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3008
    depends_on:
      - logstash
    networks:
      - logging-net

  shipping-service:
    image: node:18-alpine
    container_name: shipping-service
    working_dir: /app
    volumes:
      - ../microservices/shipping-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3009:3009"
    environment:
      - SERVICE_NAME=shipping-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3009
    depends_on:
      - logstash
    networks:
      - logging-net

  analytics-service:
    image: node:18-alpine
    container_name: analytics-service
    working_dir: /app
    volumes:
      - ../microservices/analytics-service:/app
      - ../microservices/shared:/app/shared
    command: sh -c "npm install && node index.js"
    ports:
      - "3010:3010"
    environment:
      - SERVICE_NAME=analytics-service
      - LOGSTASH_HOST=logstash
      - LOGSTASH_PORT=5000
      - PORT=3010
    depends_on:
      - logstash
    networks:
      - logging-net
COMPOSE

# ── Logstash Config ───────────────────────────────────────────────────────────
cat > elk-stack/logstash/config/logstash.yml << 'LSYML'
http.host: "0.0.0.0"
xpack.monitoring.enabled: false
pipeline.workers: 2
LSYML

cat > elk-stack/logstash/pipeline/logstash.conf << 'LSCONF'
input {
  tcp {
    port => 5000
    codec => json_lines
  }
  beats {
    port => 5044
  }
}

filter {
  if [timestamp] {
    date {
      match => ["timestamp", "ISO8601"]
      target => "@timestamp"
    }
    mutate { remove_field => ["timestamp"] }
  }
  mutate {
    add_field => { "environment" => "production" }
  }
  if [level] {
    mutate { uppercase => ["level"] }
  }
  if [duration_ms] {
    mutate { convert => { "duration_ms" => "integer" } }
  }
  if [duration_ms] and [duration_ms] > 1000 {
    mutate { add_tag => ["slow_request"] }
  }
  if [level] == "ERROR" {
    mutate { add_tag => ["error"] }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "microservices-logs-%{service}-%{+YYYY.MM.dd}"
  }
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "microservices-all-%{+YYYY.MM.dd}"
  }
}
LSCONF

# ── Shared Logger ─────────────────────────────────────────────────────────────
cat > microservices/shared/logger.js << 'LOGGER'
'use strict';
const winston = require('winston');
const net = require('net');

const SERVICE_NAME = process.env.SERVICE_NAME || 'unknown-service';
const LOGSTASH_HOST = process.env.LOGSTASH_HOST || 'localhost';
const LOGSTASH_PORT = parseInt(process.env.LOGSTASH_PORT || '5000', 10);

class LogstashTransport extends winston.Transport {
  constructor(opts) {
    super(opts);
    this.host = opts.host;
    this.port = opts.port;
  }
  log(info, callback) {
    const payload = {
      service: SERVICE_NAME,
      level: info.level,
      message: info.message,
      timestamp: new Date().toISOString(),
      ...info.meta,
    };
    const client = net.createConnection({ host: this.host, port: this.port }, () => {
      client.write(JSON.stringify(payload) + '\n');
      client.end();
    });
    client.on('error', () => {});
    callback();
  }
}

const logger = winston.createLogger({
  level: 'info',
  defaultMeta: { service: SERVICE_NAME },
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
          return `${timestamp} [${service}] ${level}: ${message} ${Object.keys(meta).length ? JSON.stringify(meta) : ''}`;
        })
      ),
    }),
    new LogstashTransport({ host: LOGSTASH_HOST, port: LOGSTASH_PORT }),
  ],
});

module.exports = logger;
LOGGER

# ── Shared Middleware ─────────────────────────────────────────────────────────
cat > microservices/shared/middleware.js << 'MIDDLEWARE'
'use strict';
const { v4: uuidv4 } = require('uuid');
const logger = require('./logger');

function correlationId(req, res, next) {
  const id = req.headers['x-correlation-id'] || uuidv4();
  req.correlationId = id;
  res.setHeader('x-correlation-id', id);
  next();
}

function requestLogger(req, res, next) {
  const start = Date.now();
  res.on('finish', () => {
    logger.info('HTTP Request', {
      method: req.method,
      path: req.path,
      status_code: res.statusCode,
      duration_ms: Date.now() - start,
      correlation_id: req.correlationId,
      client_ip: req.ip,
    });
  });
  next();
}

function errorHandler(err, req, res, next) {
  logger.error('Unhandled Error', {
    error_message: err.message,
    stack: err.stack,
    path: req.path,
    correlation_id: req.correlationId,
  });
  res.status(500).json({ error: 'Internal Server Error' });
}

module.exports = { correlationId, requestLogger, errorHandler };
MIDDLEWARE

# ── Package.json for each service ─────────────────────────────────────────────
for SVC in user-service order-service payment-service inventory-service notification-service product-service auth-service cart-service shipping-service analytics-service; do
cat > microservices/$SVC/package.json << PKGJSON
{
  "name": "$SVC",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.18.2",
    "winston": "^3.11.0",
    "uuid": "^9.0.0"
  }
}
PKGJSON
done

# ── user-service ──────────────────────────────────────────────────────────────
cat > microservices/user-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3001;
const SERVICE = 'user-service';
const users = [
  { id: 'u1', name: 'Alice Kumar', email: 'alice@demo.com', role: 'admin' },
  { id: 'u2', name: 'Bob Rajan', email: 'bob@demo.com', role: 'customer' },
];
app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));
app.get('/users', (req, res) => {
  logger.info('Fetching all users', { count: users.length });
  res.json({ users, total: users.length });
});
app.post('/users', (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) return res.status(400).json({ error: 'name and email required' });
  const user = { id: uuidv4(), name, email, role: 'customer' };
  users.push(user);
  logger.info('User created', { userId: user.id });
  res.status(201).json(user);
});
setInterval(() => logger.info('Session heartbeat', { activeUsers: users.length }), 10000);
app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} started`, { port: PORT }));
SVC

# ── order-service ─────────────────────────────────────────────────────────────
cat > microservices/order-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3002;
const SERVICE = 'order-service';
const orders = [];
app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));
app.get('/orders', (req, res) => {
  logger.info('Orders listed', { count: orders.length });
  res.json({ orders, total: orders.length });
});
app.post('/orders', (req, res) => {
  const { userId, items, totalAmount } = req.body;
  if (!userId || !items || !totalAmount) return res.status(400).json({ error: 'Missing fields' });
  const order = { id: uuidv4(), userId, items, totalAmount, status: 'PENDING', createdAt: new Date().toISOString() };
  orders.push(order);
  logger.info('Order created', { orderId: order.id, userId, totalAmount });
  res.status(201).json(order);
});
setInterval(() => logger.info('Order processing heartbeat', { totalOrders: orders.length }), 12000);
app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} started`, { port: PORT }));
SVC

# ── payment-service ───────────────────────────────────────────────────────────
cat > microservices/payment-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3003;
const SERVICE = 'payment-service';
const transactions = [];
app.get('/health', (req, res) => res.json({ status: 'ok', service: SERVICE }));
app.post('/payments', (req, res) => {
  const { orderId, amount, method = 'card' } = req.body;
  if (!orderId || !amount) return res.status(400).json({ error: 'orderId and amount required' });
  const start = Date.now();
  try {
    if (Math.random() < 0.1) throw new Error('Gateway timeout');
    const txn = { id: uuidv4(), orderId, amount, method, status: 'SUCCESS', createdAt: new Date().toISOString() };
    transactions.push(txn);
    logger.info('Payment success', { txnId: txn.id, orderId, amount, duration_ms: Date.now() - start });
    res.status(201).json(txn);
  } catch (err) {
    logger.error('Payment failed', { orderId, amount, error: err.message, duration_ms: Date.now() - start });
    res.status(502).json({ error: err.message });
  }
});
setInterval(() => {
  const total = transactions.reduce((s, t) => s + (t.amount || 0), 0);
  logger.info('Payment reconciliation', { count: transactions.length, totalAmount: total });
}, 15000);
app.use(errorHandler);
app.listen(PORT, () => logger.info(`${SERVICE} started`, { port: PORT }));
SVC

# ── inventory-service ─────────────────────────────────────────────────────────
cat > microservices/inventory-service/index.js << 'SVC'
'use strict';
const express = require('express');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3004;
const inventory = {
  'SKU-001': { name: 'Widget A', quantity: 100, reorderLevel: 20 },
  'SKU-002': { name: 'Widget B', quantity: 15, reorderLevel: 20 },
  'SKU-003': { name: 'Gadget X', quantity: 0, reorderLevel: 10 },
};
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'inventory-service' }));
app.get('/inventory', (req, res) => {
  logger.info('Inventory listed', { skuCount: Object.keys(inventory).length });
  res.json(inventory);
});
app.patch('/inventory/:sku/reserve', (req, res) => {
  const { quantity } = req.body;
  const item = inventory[req.params.sku];
  if (!item) return res.status(404).json({ error: 'SKU not found' });
  if (item.quantity < quantity) {
    logger.warn('Insufficient stock', { sku: req.params.sku, requested: quantity, available: item.quantity });
    return res.status(409).json({ error: 'Insufficient stock' });
  }
  item.quantity -= quantity;
  logger.info('Stock reserved', { sku: req.params.sku, reserved: quantity, remaining: item.quantity });
  res.json({ sku: req.params.sku, ...item });
});
setInterval(() => {
  Object.entries(inventory).forEach(([sku, item]) => {
    if (item.quantity === 0) logger.error('Out of stock alert', { sku, name: item.name });
  });
}, 14000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('inventory-service started', { port: PORT }));
SVC

# ── notification-service ──────────────────────────────────────────────────────
cat > microservices/notification-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3005;
const notifications = [];
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'notification-service' }));
app.post('/notify', (req, res) => {
  const { userId, channel, message } = req.body;
  if (!userId || !channel || !message) return res.status(400).json({ error: 'Missing fields' });
  const delivered = Math.random() > 0.05;
  const n = { id: uuidv4(), userId, channel, message, delivered, createdAt: new Date().toISOString() };
  notifications.push(n);
  if (delivered) logger.info('Notification sent', { notifId: n.id, userId, channel });
  else logger.error('Notification failed', { notifId: n.id, userId, channel });
  res.status(201).json(n);
});
setInterval(() => logger.info('Notification digest', { total: notifications.length, failed: notifications.filter(n => !n.delivered).length }), 18000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('notification-service started', { port: PORT }));
SVC

# ── product-service ───────────────────────────────────────────────────────────
cat > microservices/product-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3006;
const products = [
  { id: 'p1', name: 'Mixer Jar 1.5L', category: 'appliance', price: 899 },
  { id: 'p2', name: 'Blade Set Pro', category: 'accessory', price: 349 },
];
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'product-service' }));
app.get('/products', (req, res) => {
  logger.info('Products listed', { count: products.length });
  res.json(products);
});
app.post('/products', (req, res) => {
  const { name, price } = req.body;
  if (!name || !price) return res.status(400).json({ error: 'name and price required' });
  const p = { id: uuidv4(), name, price };
  products.push(p);
  logger.info('Product created', { productId: p.id });
  res.status(201).json(p);
});
setInterval(() => logger.info('Catalog sync', { totalProducts: products.length }), 20000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('product-service started', { port: PORT }));
SVC

# ── auth-service ──────────────────────────────────────────────────────────────
cat > microservices/auth-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3007;
const sessions = {};
const failedAttempts = {};
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'auth-service' }));
app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  failedAttempts[email] = failedAttempts[email] || 0;
  if (failedAttempts[email] >= 5) {
    logger.error('Account locked', { email, attempts: failedAttempts[email] });
    return res.status(423).json({ error: 'Account locked' });
  }
  if (!password.includes('pass')) {
    failedAttempts[email]++;
    logger.warn('Login failed', { email, failedCount: failedAttempts[email] });
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  failedAttempts[email] = 0;
  const token = uuidv4();
  sessions[token] = { email, createdAt: new Date().toISOString() };
  logger.info('Login success', { email });
  res.json({ token });
});
app.post('/auth/verify', (req, res) => {
  const { token } = req.body;
  if (!sessions[token]) {
    logger.warn('Invalid token', {});
    return res.status(401).json({ valid: false });
  }
  res.json({ valid: true, session: sessions[token] });
});
setInterval(() => logger.info('Active sessions', { count: Object.keys(sessions).length }), 14000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('auth-service started', { port: PORT }));
SVC

# ── cart-service ──────────────────────────────────────────────────────────────
cat > microservices/cart-service/index.js << 'SVC'
'use strict';
const express = require('express');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3008;
const carts = {};
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'cart-service' }));
app.get('/cart/:userId', (req, res) => {
  const cart = carts[req.params.userId] || [];
  const total = cart.reduce((s, i) => s + i.price * i.quantity, 0);
  logger.info('Cart fetched', { userId: req.params.userId, items: cart.length, total });
  res.json({ userId: req.params.userId, items: cart, total });
});
app.post('/cart/:userId/add', (req, res) => {
  const { productId, quantity, price } = req.body;
  if (!productId || !quantity || !price) return res.status(400).json({ error: 'Missing fields' });
  if (!carts[req.params.userId]) carts[req.params.userId] = [];
  const existing = carts[req.params.userId].find(i => i.productId === productId);
  if (existing) existing.quantity += quantity;
  else carts[req.params.userId].push({ productId, quantity, price });
  logger.info('Item added to cart', { userId: req.params.userId, productId, quantity });
  res.json(carts[req.params.userId]);
});
setInterval(() => logger.info('Active carts', { count: Object.keys(carts).length }), 16000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('cart-service started', { port: PORT }));
SVC

# ── shipping-service ──────────────────────────────────────────────────────────
cat > microservices/shipping-service/index.js << 'SVC'
'use strict';
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3009;
const CARRIERS = ['BlueDart', 'Delhivery', 'FedEx'];
const shipments = [];
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'shipping-service' }));
app.post('/shipments', (req, res) => {
  const { orderId, address } = req.body;
  if (!orderId || !address) return res.status(400).json({ error: 'Missing fields' });
  const carrier = CARRIERS[Math.floor(Math.random() * CARRIERS.length)];
  const s = { id: uuidv4(), orderId, address, carrier, trackingNumber: `TRK${Date.now()}`, status: 'LABEL_CREATED', createdAt: new Date().toISOString() };
  shipments.push(s);
  logger.info('Shipment created', { shipmentId: s.id, orderId, carrier, tracking: s.trackingNumber });
  res.status(201).json(s);
});
setInterval(() => logger.info('Shipment status check', { totalShipments: shipments.length }), 9000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('shipping-service started', { port: PORT }));
SVC

# ── analytics-service ─────────────────────────────────────────────────────────
cat > microservices/analytics-service/index.js << 'SVC'
'use strict';
const express = require('express');
const logger = require('./shared/logger');
const { correlationId, requestLogger, errorHandler } = require('./shared/middleware');
const app = express();
app.use(express.json()); app.use(correlationId); app.use(requestLogger);
const PORT = process.env.PORT || 3010;
const events = [];
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'analytics-service' }));
app.post('/events', (req, res) => {
  const { type, userId, data } = req.body;
  if (!type || !userId) return res.status(400).json({ error: 'type and userId required' });
  const event = { type, userId, data, timestamp: new Date().toISOString() };
  events.push(event);
  logger.info('Event tracked', { eventType: type, userId });
  res.status(201).json({ message: 'Event recorded' });
});
app.get('/analytics/summary', (req, res) => {
  const summary = events.reduce((acc, e) => { acc[e.type] = (acc[e.type] || 0) + 1; return acc; }, {});
  logger.info('Summary generated', { totalEvents: events.length });
  res.json({ totalEvents: events.length, summary });
});
setInterval(() => logger.info('Analytics report', { totalEvents: events.length }), 11000);
app.use(errorHandler);
app.listen(PORT, () => logger.info('analytics-service started', { port: PORT }));
SVC

echo -e "${GREEN}✅ All project files created${NC}"

# =============================================================================
# STEP 6 — Install AWS CloudWatch Agent
# =============================================================================
echo ""
echo -e "${YELLOW}[6/7] Installing AWS CloudWatch Agent...${NC}"

wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb

# Create log directories for CloudWatch
SERVICES=(user-service order-service payment-service inventory-service notification-service product-service auth-service cart-service shipping-service analytics-service)
for svc in "${SERVICES[@]}"; do
  sudo mkdir -p /var/log/microservices/$svc
done

# Write CloudWatch agent config
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << 'CWCONFIG'
{
  "agent": { "metrics_collection_interval": 60 },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/microservices/user-service/*.log",         "log_group_name": "/microservices/user-service",         "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/order-service/*.log",        "log_group_name": "/microservices/order-service",        "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/payment-service/*.log",      "log_group_name": "/microservices/payment-service",      "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/inventory-service/*.log",    "log_group_name": "/microservices/inventory-service",    "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/notification-service/*.log", "log_group_name": "/microservices/notification-service", "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/product-service/*.log",      "log_group_name": "/microservices/product-service",      "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/auth-service/*.log",         "log_group_name": "/microservices/auth-service",         "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/cart-service/*.log",         "log_group_name": "/microservices/cart-service",         "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/shipping-service/*.log",     "log_group_name": "/microservices/shipping-service",     "log_stream_name": "{instance_id}" },
          { "file_path": "/var/log/microservices/analytics-service/*.log",    "log_group_name": "/microservices/analytics-service",    "log_stream_name": "{instance_id}" }
        ]
      }
    },
    "force_flush_interval": 15
  }
}
CWCONFIG

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s 2>/dev/null || echo "  (CloudWatch agent will start once IAM role is attached)"

echo -e "${GREEN}✅ CloudWatch Agent installed${NC}"

# =============================================================================
# STEP 7 — Start ELK + All Microservices
# =============================================================================
echo ""
echo -e "${YELLOW}[7/7] Starting ELK Stack and all 10 microservices...${NC}"
echo -e "${CYAN}    (First run pulls Docker images — may take 3-5 minutes)${NC}"
echo ""

cd ~/centralized-logging/elk-stack
docker compose up -d

# Wait for Elasticsearch
echo -e "${YELLOW}Waiting for Elasticsearch to be ready...${NC}"
until curl -s http://localhost:9200/_cluster/health | grep -q '"status"'; do
  echo "  Still waiting..."
  sleep 10
done

echo ""
echo -e "${GREEN}"
echo "============================================================"
echo "   ✅ ALL DONE! Everything is running!"
echo "============================================================"
echo -e "${NC}"
echo -e "${CYAN}  🔍 Kibana Dashboard:${NC}    http://${PUBLIC_IP}:5601"
echo -e "${CYAN}  🔍 Elasticsearch:${NC}       http://${PUBLIC_IP}:9200"
echo ""
echo -e "${CYAN}  📦 Microservices:${NC}"
echo "     user-service         → http://${PUBLIC_IP}:3001/health"
echo "     order-service        → http://${PUBLIC_IP}:3002/health"
echo "     payment-service      → http://${PUBLIC_IP}:3003/health"
echo "     inventory-service    → http://${PUBLIC_IP}:3004/health"
echo "     notification-service → http://${PUBLIC_IP}:3005/health"
echo "     product-service      → http://${PUBLIC_IP}:3006/health"
echo "     auth-service         → http://${PUBLIC_IP}:3007/health"
echo "     cart-service         → http://${PUBLIC_IP}:3008/health"
echo "     shipping-service     → http://${PUBLIC_IP}:3009/health"
echo "     analytics-service    → http://${PUBLIC_IP}:3010/health"
echo ""
echo -e "${YELLOW}  📋 Useful commands:${NC}"
echo "     docker compose ps                     → Check all containers"
echo "     docker compose logs -f kibana         → Kibana logs"
echo "     docker compose logs -f logstash       → Logstash logs"
echo "     docker compose logs -f user-service   → Service logs"
echo "     docker compose down                   → Stop everything"
echo ""
echo -e "${YELLOW}  ⚠️  Kibana Setup (first time):${NC}"
echo "     1. Open http://${PUBLIC_IP}:5601"
echo "     2. Go to Management → Data Views → Create data view"
echo "     3. Index pattern: microservices-all-*"
echo "     4. Timestamp field: @timestamp → Save"
echo "     5. Go to Discover → see all 10 services live!"
echo ""