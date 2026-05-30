@echo off
:: ============================================================
:: Centralized Logging - ELK Stack Startup Script (Windows)
:: ============================================================
echo.
echo  ==========================================
echo   Centralized Logging - ELK Stack Setup
echo  ==========================================
echo.

:: Check Docker
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Docker is not installed or not running!
    echo Please install Docker Desktop from https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

echo [1/4] Pulling ELK images (first time may take a few minutes)...
cd elk-stack
docker-compose pull

echo.
echo [2/4] Starting Elasticsearch, Logstash, Kibana...
docker-compose up -d elasticsearch logstash kibana

echo.
echo [3/4] Waiting for Elasticsearch to be ready...
:WAIT_ES
timeout /t 5 /nobreak > nul
curl -s http://localhost:9200/_cluster/health >nul 2>&1
if %errorlevel% neq 0 (
    echo     Still waiting for Elasticsearch...
    goto WAIT_ES
)
echo     Elasticsearch is ready!

echo.
echo [4/4] Starting all 10 microservices...
docker-compose up -d user-service order-service payment-service inventory-service notification-service product-service auth-service cart-service shipping-service analytics-service

echo.
echo  ============================================
echo   All services started successfully!
echo  ============================================
echo.
echo   Kibana Dashboard:    http://localhost:5601
echo   Elasticsearch API:   http://localhost:9200
echo   Logstash:            localhost:5000 (TCP)
echo.
echo   Microservice ports:
echo     user-service:         http://localhost:3001
echo     order-service:        http://localhost:3002
echo     payment-service:      http://localhost:3003
echo     inventory-service:    http://localhost:3004
echo     notification-service: http://localhost:3005
echo     product-service:      http://localhost:3006
echo     auth-service:         http://localhost:3007
echo     cart-service:         http://localhost:3008
echo     shipping-service:     http://localhost:3009
echo     analytics-service:    http://localhost:3010
echo.
echo   To view logs: docker-compose logs -f [service-name]
echo   To stop all:  docker-compose down
echo.
pause
