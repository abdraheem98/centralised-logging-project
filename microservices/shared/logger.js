/**
 * logger.js
 * Shared Winston logger that ships logs to Logstash over TCP (JSON Lines).
 * All 10 microservices import this file.
 */

const winston = require('winston');
const net = require('net');

const SERVICE_NAME = process.env.SERVICE_NAME || 'unknown-service';
const LOGSTASH_HOST = process.env.LOGSTASH_HOST || 'localhost';
const LOGSTASH_PORT = parseInt(process.env.LOGSTASH_PORT || '5000', 10);

// ── Custom transport: sends each log to Logstash via TCP ──────────────
class LogstashTransport extends winston.Transport {
  constructor(opts) {
    super(opts);
    this.name = 'LogstashTransport';
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

    client.on('error', (err) => {
      console.error(`[LogstashTransport] Failed to send log: ${err.message}`);
    });

    callback();
  }
}

// ── Winston Logger Instance ───────────────────────────────────────────
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  defaultMeta: { service: SERVICE_NAME },
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    // Console output (pretty-printed for local dev)
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
          const metaStr = Object.keys(meta).length ? JSON.stringify(meta) : '';
          return `${timestamp} [${service}] ${level}: ${message} ${metaStr}`;
        })
      ),
    }),
    // Logstash TCP transport
    new LogstashTransport({
      host: LOGSTASH_HOST,
      port: LOGSTASH_PORT,
    }),
  ],
});

/**
 * Convenience: log an HTTP request with timing
 */
logger.logRequest = function (req, res, durationMs) {
  this.info('HTTP Request', {
    meta: {
      method: req.method,
      path: req.path,
      status_code: res.statusCode,
      duration_ms: durationMs,
      client_ip: req.ip || req.connection.remoteAddress,
      user_agent: req.headers['user-agent'],
      correlation_id: req.headers['x-correlation-id'] || null,
    },
  });
};

module.exports = logger;
