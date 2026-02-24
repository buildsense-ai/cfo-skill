#!/usr/bin/env bash
# sync-openrouter.sh — Sync spending data from OpenRouter API
# Usage: bash scripts/sync-openrouter.sh <api_key> [days]

set -euo pipefail

DB_PATH="$HOME/.accountant/accountant.db"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found. Run init-db.sh first."
  exit 1
fi

# Resolve API key: argument > credentials table > env var
API_KEY="${1:-}"

if [ -z "$API_KEY" ]; then
  API_KEY=$(sqlite3 "$DB_PATH" \
    "SELECT credential_value FROM credentials WHERE platform='openrouter' LIMIT 1" 2>/dev/null || true)
fi

if [ -z "$API_KEY" ]; then
  API_KEY="${OPENROUTER_API_KEY:-}"
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: No API key provided."
  echo "Usage: sync-openrouter.sh <api_key>"
  echo "Or store it: INSERT INTO credentials (platform, credential_value) VALUES ('openrouter', 'sk-...');"
  echo "Or set OPENROUTER_API_KEY env var."
  exit 1
fi

echo "Syncing from OpenRouter API..."

# Fetch key info
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  "https://openrouter.ai/api/v1/key")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: OpenRouter API returned HTTP $HTTP_CODE"
  echo "$BODY"
  exit 1
fi

# Parse JSON response with python (available on macOS/Linux)
python3 -c "
import json, hashlib, sys

body = json.loads('''$BODY''')
data = body.get('data', {})

label = data.get('label', 'unknown')
usage_daily = data.get('usage_daily', 0) or 0
usage_weekly = data.get('usage_weekly', 0) or 0
usage_monthly = data.get('usage_monthly', 0) or 0
usage_total = data.get('usage', 0) or 0
credit_limit = data.get('limit')
limit_remaining = data.get('limit_remaining')
is_free_tier = 1 if data.get('is_free_tier') else 0

from datetime import datetime, timezone
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')

raw = json.dumps({'label': label, 'date': today, 'daily': usage_daily}, sort_keys=True)
raw_hash = hashlib.sha256(raw.encode()).hexdigest()[:16]

limit_sql = str(credit_limit) if credit_limit is not None else 'NULL'
remaining_sql = str(limit_remaining) if limit_remaining is not None else 'NULL'

sql = f\"\"\"INSERT OR IGNORE INTO openrouter_ledger
  (api_key_label, date, usage_daily, usage_weekly, usage_monthly, usage_total,
   credit_limit, limit_remaining, is_free_tier, raw_hash)
VALUES
  ('{label}', '{today}', {usage_daily}, {usage_weekly}, {usage_monthly}, {usage_total},
   {limit_sql}, {remaining_sql}, {is_free_tier}, '{raw_hash}');\"\"\"

print(sql)
print('---SUMMARY---')
print(f'Key: {label}')
print(f'Daily: \${usage_daily:.4f}')
print(f'Weekly: \${usage_weekly:.4f}')
print(f'Monthly: \${usage_monthly:.4f}')
print(f'Total: \${usage_total:.4f}')
if limit_remaining is not None:
    print(f'Remaining: \${limit_remaining:.2f}')
print(f'Free tier: {\"Yes\" if is_free_tier else \"No\"}')
" > /tmp/accountant_sync.txt

# Extract SQL and execute
SQL_LINE=$(sed -n '1,/---SUMMARY---/p' /tmp/accountant_sync.txt | head -n -1)
sqlite3 "$DB_PATH" "$SQL_LINE"

# Print summary
echo ""
sed -n '/---SUMMARY---/,$ p' /tmp/accountant_sync.txt | tail -n +2

echo ""
echo "Sync complete. Data written to openrouter_ledger table."

rm -f /tmp/accountant_sync.txt
