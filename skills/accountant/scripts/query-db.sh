#!/usr/bin/env bash
# query-db.sh — Run SQL queries against the accountant database
# Usage: bash scripts/query-db.sh "SELECT * FROM expenses LIMIT 10"

set -euo pipefail

DB_PATH="$HOME/.accountant/accountant.db"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found at $DB_PATH"
  echo "Run init-db.sh first."
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Usage: query-db.sh <sql_query>"
  echo "Example: query-db.sh \"SELECT * FROM categories\""
  exit 1
fi

SQL="$1"

sqlite3 -header -column "$DB_PATH" "$SQL"
