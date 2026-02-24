#!/usr/bin/env bash
# generate-report.sh — Generate financial reports from accountant database
# Usage: bash scripts/generate-report.sh [period] [format] [start_date] [end_date]
# Periods: weekly, monthly, quarterly, yearly, custom
# Formats: summary, detailed, csv

set -euo pipefail

DB_PATH="$HOME/.accountant/accountant.db"
REPORTS_DIR="$HOME/.accountant/reports"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found. Run init-db.sh first."
  exit 1
fi

mkdir -p "$REPORTS_DIR"

PERIOD="${1:-monthly}"
FORMAT="${2:-summary}"
CUSTOM_START="${3:-}"
CUSTOM_END="${4:-}"

# Calculate date range based on period
case "$PERIOD" in
  weekly)
    START_DATE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
    ;;
  monthly)
    START_DATE=$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
    ;;
  quarterly)
    START_DATE=$(date -v-3m +%Y-%m-%d 2>/dev/null || date -d '3 months ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
    ;;
  yearly)
    START_DATE=$(date -v-1y +%Y-%m-%d 2>/dev/null || date -d '1 year ago' +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
    ;;
  custom)
    if [ -z "$CUSTOM_START" ] || [ -z "$CUSTOM_END" ]; then
      echo "ERROR: Custom period requires start_date and end_date"
      echo "Usage: generate-report.sh custom summary 2024-01-01 2024-03-31"
      exit 1
    fi
    START_DATE="$CUSTOM_START"
    END_DATE="$CUSTOM_END"
    ;;
  *)
    echo "ERROR: Unknown period: $PERIOD"
    echo "Valid: weekly, monthly, quarterly, yearly, custom"
    exit 1
    ;;
esac

export START_DATE END_DATE PERIOD FORMAT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORTS_DIR/report_${PERIOD}_${TIMESTAMP}"

echo "Generating $FORMAT report for $PERIOD ($START_DATE to $END_DATE)..."

# CSV format — simple sqlite3 export
if [ "$FORMAT" = "csv" ]; then
  REPORT_FILE="${REPORT_FILE}.csv"
  sqlite3 -header -csv "$DB_PATH" \
    "SELECT e.date, e.vendor, e.amount, c.name as category, e.description
     FROM expenses e
     LEFT JOIN categories c ON e.category_id = c.id
     WHERE e.date >= '$START_DATE' AND e.date <= '$END_DATE'
     ORDER BY e.date DESC;" > "$REPORT_FILE"
  echo "CSV report saved to: $REPORT_FILE"
  exit 0
fi

# Markdown report — python for richer formatting
REPORT_FILE="${REPORT_FILE}.md"

python3 << 'PYEOF' > "$REPORT_FILE"
import sqlite3, os
from datetime import datetime

db = os.path.expanduser("~/.accountant/accountant.db")
start = os.environ.get("START_DATE", "")
end = os.environ.get("END_DATE", "")
period = os.environ.get("PERIOD", "monthly")
fmt = os.environ.get("FORMAT", "summary")

conn = sqlite3.connect(db)
conn.row_factory = sqlite3.Row
now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

lines = [f"# Financial Report — {start} to {end}", "",
         f"Generated: {now}", f"Period: {period}", ""]

# Summary
row = conn.execute(
    "SELECT COALESCE(SUM(amount),0) as total, COUNT(*) as count "
    "FROM expenses WHERE date >= ? AND date <= ?", (start, end)
).fetchone()
total, count = row["total"], row["count"]
days = max((datetime.strptime(end, "%Y-%m-%d") - datetime.strptime(start, "%Y-%m-%d")).days, 1)

lines += ["## Summary", "", "| Metric | Value |", "|--------|-------|",
    f"| Total Expenses | ${total:,.2f} |",
    f"| Transaction Count | {count} |",
    f"| Daily Average | ${total/days:,.2f} |",
    f"| Period Days | {days} |", ""]

# By category
rows = conn.execute(
    "SELECT c.name, COALESCE(SUM(e.amount),0) as total, COUNT(*) as cnt "
    "FROM expenses e JOIN categories c ON e.category_id = c.id "
    "WHERE e.date >= ? AND e.date <= ? GROUP BY c.id ORDER BY total DESC",
    (start, end)).fetchall()
if rows:
    lines += ["## By Category", "", "| Category | Amount | Count | % |",
              "|----------|--------|-------|---|"]
    for r in rows:
        pct = (r["total"] / total * 100) if total > 0 else 0
        lines.append(f"| {r['name']} | ${r['total']:,.2f} | {r['cnt']} | {pct:.1f}% |")
    lines.append("")

# Top vendors
rows = conn.execute(
    "SELECT vendor, COALESCE(SUM(amount),0) as total, COUNT(*) as cnt "
    "FROM expenses WHERE date >= ? AND date <= ? AND vendor != '' "
    "GROUP BY vendor ORDER BY total DESC LIMIT 10", (start, end)).fetchall()
if rows:
    lines += ["## Top Vendors", "", "| Vendor | Amount | Count |",
              "|--------|--------|-------|"]
    for r in rows:
        lines.append(f"| {r['vendor']} | ${r['total']:,.2f} | {r['cnt']} |")
    lines.append("")

# Recurrent expenses
rows = conn.execute(
    "SELECT name, amount, frequency, next_due_date "
    "FROM recurrent_expenses WHERE active=1 ORDER BY amount DESC").fetchall()
if rows:
    lines += ["## Active Recurrent Expenses", "",
              "| Name | Amount | Frequency | Next Due |",
              "|------|--------|-----------|----------|"]
    for r in rows:
        lines.append(f"| {r['name']} | ${r['amount']:,.2f} | {r['frequency']} | {r['next_due_date'] or 'N/A'} |")
    lines.append("")

# OpenRouter spending
rows = conn.execute(
    "SELECT api_key_label, date, usage_daily, usage_monthly, limit_remaining "
    "FROM openrouter_ledger WHERE date >= ? AND date <= ? "
    "ORDER BY date DESC LIMIT 10", (start, end)).fetchall()
if rows:
    lines += ["## OpenRouter API Spending", "",
              "| Key | Date | Daily | Monthly | Remaining |",
              "|-----|------|-------|---------|-----------|"]
    for r in rows:
        rem = f"${r['limit_remaining']:.2f}" if r["limit_remaining"] else "N/A"
        lines.append(f"| {r['api_key_label']} | {r['date']} | ${r['usage_daily']:.4f} | ${r['usage_monthly']:.4f} | {rem} |")
    lines.append("")

# Detailed transactions
if fmt == "detailed":
    rows = conn.execute(
        "SELECT e.date, e.vendor, e.amount, c.name as category, e.description "
        "FROM expenses e LEFT JOIN categories c ON e.category_id = c.id "
        "WHERE e.date >= ? AND e.date <= ? ORDER BY e.date DESC",
        (start, end)).fetchall()
    if rows:
        lines += ["## All Transactions", "",
                  "| Date | Vendor | Amount | Category | Description |",
                  "|------|--------|--------|----------|-------------|"]
        for r in rows:
            desc = (r['description'] or '')[:50]
            lines.append(f"| {r['date']} | {r['vendor']} | ${r['amount']:,.2f} | {r['category'] or 'N/A'} | {desc} |")
        lines.append("")

conn.close()
print("\n".join(lines))
PYEOF

# Log report generation
sqlite3 "$DB_PATH" \
  "INSERT INTO reports (period, format, file_path) VALUES ('$PERIOD', '$FORMAT', '$REPORT_FILE');"

echo "Report saved to: $REPORT_FILE"
