#!/bin/bash

# Script to reproduce alert execution history issue in a CUSTOM KIBANA SPACE
# This creates a custom space, then creates an alert rule in that space

# ============================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================
ES_ENDPOINT="https://your-cluster.es.region.cloud.elastic-cloud.com:9243"
KIBANA_ENDPOINT="https://your-cluster.kb.region.cloud.elastic-cloud.com:9243"
USERNAME="your-username"
PASSWORD="your-password"
SPACE_ID="test-space"
SPACE_NAME="Test Space for Alert History"

# ============================================
# DO NOT MODIFY BELOW THIS LINE
# ============================================

echo "=========================================="
echo "Alert Execution History Test - Custom Space"
echo "=========================================="
echo ""

# Step 1: Create custom Kibana space
echo "Step 1: Creating custom Kibana space '$SPACE_ID'..."
SPACE_RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" -X POST "$KIBANA_ENDPOINT/api/spaces/space" \
  -H 'Content-Type: application/json' -H 'kbn-xsrf: true' -d @- <<EOF
{
  "id": "$SPACE_ID",
  "name": "$SPACE_NAME",
  "description": "Test space to reproduce execution history issue",
  "disabledFeatures": []
}
EOF
)

if echo "$SPACE_RESPONSE" | grep -q "error"; then
  echo "⚠ Space might already exist or error occurred:"
  echo "$SPACE_RESPONSE" | jq -r '.message // .error'
else
  echo "✓ Space created: $SPACE_ID"
fi
echo ""

# Step 2: Create test data
echo "Step 2: Creating test data..."
for i in {1..10}; do
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  STATUS=$((500 + RANDOM % 100))
  curl -s -u "$USERNAME:$PASSWORD" -X POST "$ES_ENDPOINT/test-space-alert-data/_doc" \
    -H 'Content-Type: application/json' -d @- > /dev/null <<EOF
{
  "@timestamp": "$TIMESTAMP",
  "status_code": $STATUS,
  "message": "Test error in custom space $i"
}
EOF
  echo "  Created document $i"
done
echo "✓ Test data created"
echo ""

# Step 3: Create alert rule IN THE CUSTOM SPACE
echo "Step 3: Creating test alert rule in custom space '$SPACE_ID'..."
RULE_RESPONSE=$(curl -s -u "$USERNAME:$PASSWORD" -X POST "$KIBANA_ENDPOINT/s/$SPACE_ID/api/alerting/rule" \
  -H 'Content-Type: application/json' -H 'kbn-xsrf: true' -d @- <<'EOF'
{
  "name": "Test Alert - Custom Space History Check",
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
    "index": ["test-space-alert-data"],
    "timeField": "@timestamp"
  },
  "tags": ["test", "custom-space"]
}
EOF
)

RULE_ID=$(echo "$RULE_RESPONSE" | jq -r '.id')
echo "✓ Alert rule created with ID: $RULE_ID"
echo "✓ Rule is in space: $SPACE_ID"
echo ""

# Step 4: Wait for executions
echo "Step 4: Waiting 5 seconds for alert to execute..."
sleep 5
echo "✓ Wait complete"
echo ""

# Step 5: Check event log
echo "Step 5: Checking event log for executions..."
EVENT_COUNT=$(curl -s -u "$USERNAME:$PASSWORD" -X GET "$ES_ENDPOINT/.kibana-event-log*/_count" \
  -H 'Content-Type: application/json' -d @- <<EOF | jq -r '.count'
{
  "query": {
    "bool": {
      "must": [
        {"match": {"rule.id": "$RULE_ID"}},
        {"term": {"kibana.space_ids": "$SPACE_ID"}}
      ]
    }
  }
}
EOF
)

echo "✓ Found $EVENT_COUNT events in .kibana-event-log index for space '$SPACE_ID'"
echo ""

# Step 6: Verify space_ids in events
echo "Step 6: Checking space_ids in sample events:"
curl -s -u "$USERNAME:$PASSWORD" -X GET "$ES_ENDPOINT/.kibana-event-log*/_search" \
  -H 'Content-Type: application/json' -d @- <<EOF | jq -r '.hits.hits[]._source | "  - \(.["@timestamp"]) | Space: \(.kibana.space_ids[0]) | \(.event.outcome)"'
{
  "size": 3,
  "query": {
    "bool": {
      "must": [
        {"match": {"rule.id": "$RULE_ID"}},
        {"term": {"event.action": "execute"}}
      ]
    }
  },
  "sort": [{"@timestamp": {"order": "desc"}}],
  "_source": ["@timestamp", "event.outcome", "kibana.space_ids", "message"]
}
EOF

echo ""
echo "=========================================="
echo "RESULTS:"
echo "=========================================="
echo "Space ID: $SPACE_ID"
echo "Rule ID: $RULE_ID"
echo "Events in ES: $EVENT_COUNT"
echo ""
echo "NOW CHECK KIBANA UI:"
echo "1. Go to Kibana and switch to space: '$SPACE_ID'"
echo "   (Top left corner → Spaces menu)"
echo "2. Go to Stack Management → Rules"
echo "3. Find: 'Test Alert - Custom Space History Check'"
echo "4. Click on it and go to the 'History' tab"
echo "5. Does the UI show execution history?"
echo ""
echo "IMPORTANT: You MUST be in the '$SPACE_ID' space"
echo "to see this rule in the UI!"
echo ""
echo "If NO execution history appears in UI but"
echo "events exist in ES, this confirms the"
echo "space-specific bug."
echo "=========================================="
