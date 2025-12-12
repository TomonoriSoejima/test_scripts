#!/bin/bash

# Script to reproduce the alert execution history issue
# This creates a test alert rule and verifies if execution history appears in Kibana UI

# ============================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================
ES_ENDPOINT="https://your-cluster.es.region.cloud.elastic-cloud.com:9243"
KIBANA_ENDPOINT="https://your-cluster.kb.region.cloud.elastic-cloud.com:9243"
USERNAME="your-username"
PASSWORD="your-password"

# ============================================
# DO NOT MODIFY BELOW THIS LINE
# ============================================

echo "=========================================="
echo "Alert Execution History Test"
echo "=========================================="
echo ""

# Step 1: Create test data
echo "Step 1: Creating test data..."
for i in {1..10}; do
  curl -s -u "$USERNAME:$PASSWORD" -X POST "$ES_ENDPOINT/test-alert-data/_doc" \
    -H 'Content-Type: application/json' -d"{
    \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
    \"status_code\": $((500 + RANDOM % 100)),
    \"message\": \"Test error $i\"
  }" > /dev/null
  echo "  Created document $i"
done
echo "✓ Test data created"
echo ""

# Step 2: Create alert rule
echo "Step 2: Creating test alert rule..."
RULE_RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" -X POST "$KIBANA_ENDPOINT/api/alerting/rule" \
  -H 'Content-Type: application/json' -H 'kbn-xsrf: true' -d'{
  "name": "Test Alert - Execution History Check",
  "rule_type_id": ".es-query",
  "enabled": true,
  "consumer": "stackAlerts",
  "schedule": {
    "interval": "1m"
  },
  "actions": [],
  "params": {
    "searchType": "esQuery",
    "timeWindowSize": 5,
    "timeWindowUnit": "m",
    "threshold": [1],
    "thresholdComparator": ">=",
    "size": 100,
    "esQuery": "{\"query\":{\"bool\":{\"must\":[{\"range\":{\"status_code\":{\"gte\":500}}}]}}}",
    "aggType": "count",
    "groupBy": "all",
    "termSize": 5,
    "excludeHitsFromPreviousRun": false,
    "sourceFields": [],
    "index": ["test-alert-data"],
    "timeField": "@timestamp"
  },
  "tags": ["test"]
}')

RULE_ID=$(echo "$RULE_RESPONSE" | jq -r '.id')
echo "✓ Alert rule created with ID: $RULE_ID"
echo ""

# Step 3: Wait for executions
echo "Step 3: Waiting 3 minutes for alert to execute..."
sleep 180
echo "✓ Wait complete"
echo ""

# Step 4: Check event log
echo "Step 4: Checking event log for executions..."
EVENT_COUNT=$(curl -s -u "$USERNAME:$PASSWORD" -X GET "$ES_ENDPOINT/.kibana-event-log*/_count" \
  -H 'Content-Type: application/json' -d"{
  \"query\": {
    \"match\": {
      \"rule.id\": \"$RULE_ID\"
    }
  }
}" | jq -r '.count')

echo "✓ Found $EVENT_COUNT events in .kibana-event-log index"
echo ""

# Step 5: Show sample events
echo "Step 5: Sample execution events:"
curl -s -u "$USERNAME:$PASSWORD" -X GET "$ES_ENDPOINT/.kibana-event-log*/_search" \
  -H 'Content-Type: application/json' -d"{
  \"size\": 3,
  \"query\": {
    \"bool\": {
      \"must\": [
        {\"match\": {\"rule.id\": \"$RULE_ID\"}},
        {\"term\": {\"event.action\": \"execute\"}}
      ]
    }
  },
  \"sort\": [{\"@timestamp\": {\"order\": \"desc\"}}]
}" | jq -r '.hits.hits[]._source | "  - \(.["@timestamp"]) | \(.event.outcome) | \(.message)"'

echo ""
echo "=========================================="
echo "RESULTS:"
echo "=========================================="
echo "Rule ID: $RULE_ID"
echo "Events in ES: $EVENT_COUNT"
echo ""
echo "NOW CHECK KIBANA UI:"
echo "1. Go to Stack Management → Rules"
echo "2. Find: 'Test Alert - Execution History Check'"
echo "3. Click on it and go to the 'History' tab"
echo "4. Does the UI show execution history?"
echo ""
echo "If NO execution history appears in UI but"
echo "events exist in ES, this confirms the bug."
echo "=========================================="
