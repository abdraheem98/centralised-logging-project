# Centralized Logging — Training Project
## 10 Microservices → ELK Stack + AWS CloudWatch

---

## What's Inside

```
centralized-logging-project/
├── elk-stack/
│   ├── docker-compose.yml              ← ELK + all 10 services
│   └── logstash/
│       ├── pipeline/logstash.conf      ← Log parsing pipeline
│       └── config/logstash.yml
│
├── microservices/
│   ├── shared/
│   │   ├── logger.js                   ← Winston + Logstash TCP transport
│   │   └── middleware.js               ← Correlation ID + request logger
│   ├── user-service/         (port 3001)
│   ├── order-service/        (port 3002)
│   ├── payment-service/      (port 3003)
│   ├── inventory-service/    (port 3004)
│   ├── notification-service/ (port 3005)
│   ├── product-service/      (port 3006)
│   ├── auth-service/         (port 3007)
│   ├── cart-service/         (port 3008)
│   ├── shipping-service/     (port 3009)
│   └── analytics-service/    (port 3010)
│
├── cloudwatch/
│   ├── cloudwatch-agent-config.json    ← CW Agent config for all 10 services
│   ├── setup-cloudwatch.sh             ← AWS provisioning script
│   └── cloudwatch-insights-queries.txt ← 12 ready-to-use queries
│
├── scripts/
│   ├── start-elk.bat                   ← Start everything (Windows)
│   └── generate-traffic.bat            ← Send demo logs to all services
│
├── monitoring/
│   └── kibana-setup.json               ← Kibana dashboard instructions
│
└── docs/
    └── Centralized-Logging-Session-Guide.docx
```

---

## Quick Start (Windows)

1. Install **Docker Desktop** from https://www.docker.com
2. Open a terminal in this folder
3. Run: `scripts\start-elk.bat`
4. Open Kibana: http://localhost:5601
5. Open a second terminal and run: `scripts\generate-traffic.bat`
6. In Kibana, create an index pattern: `microservices-all-*`
7. Go to **Discover** and see all 10 services logging in real time!

---

## Services and Health Endpoints

| Service              | Port | Health Check URL                  |
|----------------------|------|-----------------------------------|
| user-service         | 3001 | http://localhost:3001/health      |
| order-service        | 3002 | http://localhost:3002/health      |
| payment-service      | 3003 | http://localhost:3003/health      |
| inventory-service    | 3004 | http://localhost:3004/health      |
| notification-service | 3005 | http://localhost:3005/health      |
| product-service      | 3006 | http://localhost:3006/health      |
| auth-service         | 3007 | http://localhost:3007/health      |
| cart-service         | 3008 | http://localhost:3008/health      |
| shipping-service     | 3009 | http://localhost:3009/health      |
| analytics-service    | 3010 | http://localhost:3010/health      |
| Kibana               | 5601 | http://localhost:5601             |
| Elasticsearch        | 9200 | http://localhost:9200/_cluster/health |

---

## Stopping Everything

```bash
cd elk-stack
docker-compose down
```

To also delete Elasticsearch data:
```bash
docker-compose down -v
```
