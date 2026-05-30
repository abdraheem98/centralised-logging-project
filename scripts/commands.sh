# Run this in your EC2 SSH terminal
while true; do

  # user-service
  curl -s http://localhost:3001/users > /dev/null
  curl -s -X POST http://localhost:3001/users \
    -H "Content-Type: application/json" \
    -d '{"name":"Demo User","email":"demo@test.com"}' > /dev/null

  # auth-service — success + failure mix
  curl -s -X POST http://localhost:3007/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"alice@demo.com","password":"password123"}' > /dev/null
  curl -s -X POST http://localhost:3007/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"bob@demo.com","password":"wrongpass"}' > /dev/null

  # product + cart
  curl -s http://localhost:3006/products > /dev/null
  curl -s -X POST http://localhost:3008/cart/u1/add \
    -H "Content-Type: application/json" \
    -d '{"productId":"p1","quantity":2,"price":899}' > /dev/null

  # order + payment
  curl -s -X POST http://localhost:3002/orders \
    -H "Content-Type: application/json" \
    -d '{"userId":"u1","items":[{"productId":"p1","qty":1}],"totalAmount":899}' > /dev/null
  curl -s -X POST http://localhost:3003/payments \
    -H "Content-Type: application/json" \
    -d '{"orderId":"order-001","amount":899,"method":"card"}' > /dev/null

  # inventory
  curl -s http://localhost:3004/inventory > /dev/null
  curl -s -X PATCH http://localhost:3004/inventory/SKU-002/reserve \
    -H "Content-Type: application/json" \
    -d '{"quantity":2}' > /dev/null

  # notification + shipping
  curl -s -X POST http://localhost:3005/notify \
    -H "Content-Type: application/json" \
    -d '{"userId":"u1","channel":"email","message":"Order confirmed!"}' > /dev/null
  curl -s -X POST http://localhost:3009/shipments \
    -H "Content-Type: application/json" \
    -d '{"orderId":"order-001","address":"Chennai, TN"}' > /dev/null

  # analytics
  curl -s -X POST http://localhost:3010/events \
    -H "Content-Type: application/json" \
    -d '{"type":"product_viewed","userId":"u1","data":{}}' > /dev/null

  echo "[$(date '+%H:%M:%S')] Traffic sent to all 10 services"
  sleep 3
done