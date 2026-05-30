#!/bin/bash
# =============================================================================
# AWS CloudWatch Setup Script for Microservices Centralized Logging
# Run on each EC2 instance or as part of ECS task setup
# =============================================================================

set -e
REGION=${AWS_REGION:-"ap-south-1"}  # Default: Mumbai (closest to Chennai)
LOG_GROUP_PREFIX="/microservices"

echo "=== Installing CloudWatch Agent ==="
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

echo "=== Copying agent config ==="
sudo cp cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== Creating log directories ==="
SERVICES=(user-service order-service payment-service inventory-service notification-service product-service auth-service cart-service shipping-service analytics-service)
for svc in "${SERVICES[@]}"; do
  sudo mkdir -p /var/log/microservices/$svc
  sudo chmod 755 /var/log/microservices/$svc
done

echo "=== Creating CloudWatch Log Groups ==="
for svc in "${SERVICES[@]}"; do
  aws logs create-log-group \
    --log-group-name "$LOG_GROUP_PREFIX/$svc" \
    --region $REGION 2>/dev/null || echo "Log group $LOG_GROUP_PREFIX/$svc already exists"

  # Set retention policy
  RETENTION=14
  if [[ "$svc" == "auth-service" ]]; then RETENTION=90; fi
  if [[ "$svc" == "payment-service" || "$svc" == "shipping-service" ]]; then RETENTION=30; fi
  if [[ "$svc" == "analytics-service" ]]; then RETENTION=60; fi

  aws logs put-retention-policy \
    --log-group-name "$LOG_GROUP_PREFIX/$svc" \
    --retention-in-days $RETENTION \
    --region $REGION
  echo "  -> $svc: retention = $RETENTION days"
done

echo "=== Starting CloudWatch Agent ==="
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

echo "=== Creating CloudWatch Metric Filters ==="
for svc in "${SERVICES[@]}"; do
  # Filter for ERROR level logs
  aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP_PREFIX/$svc" \
    --filter-name "${svc}-error-count" \
    --filter-pattern '"level":"ERROR"' \
    --metric-transformations \
      metricName="${svc}-errors",metricNamespace="Microservices/Errors",metricValue="1",defaultValue="0" \
    --region $REGION
done

echo "=== Creating CloudWatch Alarms ==="
for svc in "${SERVICES[@]}"; do
  aws cloudwatch put-metric-alarm \
    --alarm-name "${svc}-high-error-rate" \
    --alarm-description "High error rate in $svc" \
    --metric-name "${svc}-errors" \
    --namespace "Microservices/Errors" \
    --statistic "Sum" \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 10 \
    --comparison-operator "GreaterThanThreshold" \
    --region $REGION
  echo "  -> Alarm created for $svc"
done

echo ""
echo "=== CloudWatch setup complete! ==="
echo "View logs at: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
