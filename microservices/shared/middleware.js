/**
 * middleware.js
 * Express middleware shared by all 10 microservices.
 * Attaches correlation IDs and logs every request automatically.
 */

const { v4: uuidv4 } = require('uuid');
const logger = require('./logger');

/**
 * Attach a correlation ID to every request.
 * Reads X-Correlation-ID from headers if present, otherwise generates one.
 */
function correlationId(req, res, next) {
  const id = req.headers['x-correlation-id'] || uuidv4();
  req.correlationId = id;
  res.setHeader('x-correlation-id', id);
  next();
}

/**
 * Log every HTTP request + response with timing.
 */
function requestLogger(req, res, next) {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info('HTTP Request', {
      method: req.method,
      path: req.path,
      status_code: res.statusCode,
      duration_ms: duration,
      correlation_id: req.correlationId,
      client_ip: req.ip,
    });
  });

  next();
}

/**
 * Catch unhandled errors and log them before sending a 500 response.
 */
function errorHandler(err, req, res, next) {
  logger.error('Unhandled Error', {
    error_message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    correlation_id: req.correlationId,
  });

  res.status(500).json({ error: 'Internal Server Error', correlationId: req.correlationId });
}

module.exports = { correlationId, requestLogger, errorHandler };
