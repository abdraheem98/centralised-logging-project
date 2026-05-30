@echo off
:: ============================================================
:: Generate demo traffic across all 10 microservices
:: This creates realistic log entries visible in Kibana
:: ============================================================
echo Generating demo traffic across all microservices...
echo Press Ctrl+C to stop.
echo.

:LOOP
:: --- User Service ---
curl -s -X GET http://localhost:3001/users > nul
curl -s -X POST http://localhost:3001/users -H "Content-Type: application/json" -d "{\"name\":\"Demo User\",\"email\":\"demo%RANDOM%@test.com\"}" > nul

:: --- Auth Service ---
curl -s -X POST http://localhost:3007/auth/login -H "Content-Type: application/json" -d "{\"email\":\"alice@demo.com\",\"password\":\"password123\"}" > nul
curl -s -X POST http://localhost:3007/auth/login -H "Content-Type: application/json" -d "{\"email\":\"bob@demo.com\",\"password\":\"wrongpassword\"}" > nul

:: --- Product Service ---
curl -s -X GET http://localhost:3006/products > nul
curl -s -X GET http://localhost:3006/products/p1 > nul

:: --- Cart Service ---
curl -s -X POST http://localhost:3008/cart/u1/add -H "Content-Type: application/json" -d "{\"productId\":\"p1\",\"quantity\":2,\"price\":899}" > nul
curl -s -X GET http://localhost:3008/cart/u1 > nul

:: --- Inventory Service ---
curl -s -X GET http://localhost:3004/inventory > nul
curl -s -X PATCH http://localhost:3004/inventory/SKU-002/reserve -H "Content-Type: application/json" -d "{\"quantity\":2}" > nul

:: --- Order Service ---
curl -s -X POST http://localhost:3002/orders -H "Content-Type: application/json" -d "{\"userId\":\"u1\",\"items\":[{\"productId\":\"p1\",\"qty\":1}],\"totalAmount\":899}" > nul
curl -s -X GET http://localhost:3002/orders > nul

:: --- Payment Service ---
curl -s -X POST http://localhost:3003/payments -H "Content-Type: application/json" -d "{\"orderId\":\"demo-order-1\",\"amount\":899,\"method\":\"card\"}" > nul

:: --- Notification Service ---
curl -s -X POST http://localhost:3005/notify -H "Content-Type: application/json" -d "{\"userId\":\"u1\",\"channel\":\"email\",\"message\":\"Order confirmed!\",\"subject\":\"Order Update\"}" > nul

:: --- Shipping Service ---
curl -s -X POST http://localhost:3009/shipments -H "Content-Type: application/json" -d "{\"orderId\":\"demo-order-1\",\"address\":\"123 Main St, Chennai, TN\"}" > nul

:: --- Analytics Service ---
curl -s -X POST http://localhost:3010/events -H "Content-Type: application/json" -d "{\"type\":\"product_viewed\",\"userId\":\"u1\",\"data\":{\"productId\":\"p1\"}}" > nul
curl -s -X GET http://localhost:3010/analytics/summary > nul

echo [%TIME%] Traffic batch sent to all 10 services...
timeout /t 3 /nobreak > nul
goto LOOP
