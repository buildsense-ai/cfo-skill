#!/usr/bin/env bash
# auto-fetch.sh — Phase 3 automation: fetch data from all stored credentials
# Usage: bash scripts/auto-fetch.sh [--dry-run]
# Iterates credentials table + user-profile.json platforms, fetches data automatically

set -euo pipefail

DB_PATH="$HOME/.accountant/accountant.db"
PROFILE_PATH="$HOME/.accountant/user-profile.json"
SCRIPTS_DIR="$HOME/.accountant/scripts"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found. Run init-db.sh first."
  exit 1
fi

DRY_RUN="${1:-}"
FETCHED=0
FAILED=0
SKIPPED=0

echo "=== Auto-Fetch: Phase 3 Automation ==="
echo "Time: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo ""

# Check phase
PHASE=$(sqlite3 "$DB_PATH" "SELECT CASE \
  WHEN (SELECT COUNT(*) FROM expense_sources) < 3 OR (SELECT COUNT(*) FROM recurrent_expenses) = 0 THEN 1 \
  WHEN (SELECT COUNT(*) FROM credentials) = 0 THEN 2 \
  ELSE 3 END")

if [ "$PHASE" != "3" ] && [ "$DRY_RUN" != "--force" ]; then
  echo "WARNING: Current phase is $PHASE (not Phase 3)."
  echo "Auto-fetch works best in Phase 3. Use --force to run anyway."
  exit 0
fi

# Iterate all stored credentials
echo "--- Fetching from stored credentials ---"

CREDS=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT platform, credential_type, credential_value FROM credentials")

if [ -z "$CREDS" ]; then
  echo "No credentials stored. Nothing to auto-fetch."
  exit 0
fi

echo "$CREDS" | while IFS='|' read -r PLATFORM CRED_TYPE CRED_VALUE; do
  echo "[$PLATFORM] type=$CRED_TYPE"

  if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "  [DRY RUN] Would fetch from $PLATFORM"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  case "$PLATFORM" in
    openrouter)
      echo "  Syncing OpenRouter via API..."
      if bash "$SCRIPTS_DIR/sync-openrouter.sh" "$CRED_VALUE" 2>&1; then
        echo "  [OK] OpenRouter synced"
        FETCHED=$((FETCHED + 1))
      else
        echo "  [FAIL] OpenRouter sync failed"
        FAILED=$((FAILED + 1))
      fi
      ;;
    *)
      echo "  [SKIP] No auto-fetch handler for $PLATFORM"
      echo "  (Agent can handle this via conversation)"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac
  echo ""
done

# Check for upcoming recurrent expenses
echo "--- Recurrent Expense Reminders ---"
UPCOMING=$(sqlite3 -header -column "$DB_PATH" \
  "SELECT name, amount, frequency, next_due_date
   FROM recurrent_expenses
   WHERE active=1
     AND next_due_date BETWEEN date('now') AND date('now','+7 days')
   ORDER BY next_due_date")

if [ -n "$UPCOMING" ]; then
  echo "$UPCOMING"
else
  echo "No recurrent expenses due in the next 7 days."
fi

echo ""
echo "=== Auto-Fetch Complete ==="
