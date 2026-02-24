#!/usr/bin/env bash
# balance-sheet.sh — Generate balance sheet (income vs expenses)
# Usage: bash scripts/balance-sheet.sh [period] [start_date] [end_date]
# Periods: weekly, monthly, quarterly, yearly, custom

set -euo pipefail

DB_PATH="$HOME/.accountant/accountant.db"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found. Run init-db.sh first."
  exit 1
fi

PERIOD="${1:-monthly}"
CUSTOM_START="${2:-}"
CUSTOM_END="${3:-}"

# Calculate date range
case "$PERIOD" in
  weekly)
    START=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
    END=$(date +%Y-%m-%d) ;;
  monthly)
    START=$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)
    END=$(date +%Y-%m-%d) ;;
  quarterly)
    START=$(date -v-3m +%Y-%m-%d 2>/dev/null || date -d '3 months ago' +%Y-%m-%d)
    END=$(date +%Y-%m-%d) ;;
  yearly)
    START=$(date -v-1y +%Y-%m-%d 2>/dev/null || date -d '1 year ago' +%Y-%m-%d)
    END=$(date +%Y-%m-%d) ;;
  custom)
    [ -z "$CUSTOM_START" ] || [ -z "$CUSTOM_END" ] && \
      echo "Usage: balance-sheet.sh custom <start> <end>" && exit 1
    START="$CUSTOM_START"
    END="$CUSTOM_END" ;;
  *)
    echo "ERROR: Unknown period: $PERIOD" && exit 1 ;;
esac

echo "=== Balance Sheet ==="
echo "Period: $START to $END ($PERIOD)"
echo ""

# Total income
TOTAL_INCOME=$(sqlite3 "$DB_PATH" \
  "SELECT COALESCE(SUM(amount),0) FROM income WHERE date BETWEEN '$START' AND '$END'")

# Total expenses
TOTAL_EXPENSES=$(sqlite3 "$DB_PATH" \
  "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date BETWEEN '$START' AND '$END'")

# Net balance
NET=$(python3 -c "print(round($TOTAL_INCOME - $TOTAL_EXPENSES, 2))")

echo "--- Summary ---"
printf "  Total Income:    $%'.2f\n" "$TOTAL_INCOME"
printf "  Total Expenses:  $%'.2f\n" "$TOTAL_EXPENSES"
printf "  Net Balance:     $%'.2f\n" "$NET"
echo ""

# Income breakdown by source
echo "--- Income by Source ---"
INCOME_DETAIL=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT COALESCE(source,'Unknown'), SUM(amount), COUNT(*)
   FROM income
   WHERE date BETWEEN '$START' AND '$END'
   GROUP BY source
   ORDER BY SUM(amount) DESC")

if [ -n "$INCOME_DETAIL" ]; then
  echo "$INCOME_DETAIL" | while IFS='|' read -r SRC AMT CNT; do
    printf "  %-25s $%'.2f  (%d entries)\n" "$SRC" "$AMT" "$CNT"
  done
else
  echo "  (no income recorded)"
fi
echo ""

# Expense breakdown by category
echo "--- Expenses by Category ---"
EXP_DETAIL=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT COALESCE(c.name,'Uncategorized'), SUM(e.amount), COUNT(*)
   FROM expenses e
   LEFT JOIN categories c ON e.category_id = c.id
   WHERE e.date BETWEEN '$START' AND '$END'
   GROUP BY c.name
   ORDER BY SUM(e.amount) DESC")

if [ -n "$EXP_DETAIL" ]; then
  echo "$EXP_DETAIL" | while IFS='|' read -r CAT AMT CNT; do
    printf "  %-25s $%'.2f  (%d entries)\n" "$CAT" "$AMT" "$CNT"
  done
else
  echo "  (no expenses recorded)"
fi
echo ""

# Top 5 vendors by spend
echo "--- Top Vendors ---"
TOP_VENDORS=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT COALESCE(vendor,'Unknown'), SUM(amount), COUNT(*)
   FROM expenses
   WHERE date BETWEEN '$START' AND '$END'
     AND vendor != ''
   GROUP BY vendor
   ORDER BY SUM(amount) DESC
   LIMIT 5")

if [ -n "$TOP_VENDORS" ]; then
  echo "$TOP_VENDORS" | while IFS='|' read -r VND AMT CNT; do
    printf "  %-25s $%'.2f  (%d txns)\n" "$VND" "$AMT" "$CNT"
  done
else
  echo "  (no vendor data)"
fi
echo ""

# Active recurrent expenses
echo "--- Active Recurrent Expenses ---"
RECURRENTS=$(sqlite3 -separator '|' "$DB_PATH" \
  "SELECT name, amount, frequency, next_due_date
   FROM recurrent_expenses
   WHERE active=1
   ORDER BY amount DESC")

if [ -n "$RECURRENTS" ]; then
  echo "$RECURRENTS" | while IFS='|' read -r NAME AMT FREQ DUE; do
    printf "  %-20s $%'.2f  %-10s  next: %s\n" "$NAME" "$AMT" "$FREQ" "$DUE"
  done
else
  echo "  (no recurrent expenses)"
fi
echo ""

# Status indicator
if [ "$(python3 -c "print('surplus' if $TOTAL_INCOME >= $TOTAL_EXPENSES else 'deficit')")" = "surplus" ]; then
  echo "Status: SURPLUS (+$NET)"
else
  echo "Status: DEFICIT ($NET)"
fi
echo "=== End Balance Sheet ==="
