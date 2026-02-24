#!/usr/bin/env bash
# init-db.sh — Initialize the accountant SQLite database
# Usage: bash scripts/init-db.sh

set -euo pipefail

DB_DIR="$HOME/.accountant"
DB_PATH="$DB_DIR/accountant.db"
SCRIPTS_DIR="$DB_DIR/scripts"
REPORTS_DIR="$DB_DIR/reports"

mkdir -p "$DB_DIR" "$SCRIPTS_DIR" "$REPORTS_DIR"

# Copy scripts to ~/.accountant/scripts/ for global access
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$SKILL_DIR/scripts" ]; then
  cp -f "$SKILL_DIR/scripts/"*.sh "$SCRIPTS_DIR/" 2>/dev/null || true
  chmod +x "$SCRIPTS_DIR/"*.sh 2>/dev/null || true
fi

# Copy user-profile.json template if not exists
PROFILE_PATH="$DB_DIR/user-profile.json"
if [ ! -f "$PROFILE_PATH" ] && [ -f "$SKILL_DIR/user-profile.json" ]; then
  cp "$SKILL_DIR/user-profile.json" "$PROFILE_PATH"
  echo "Created user profile at $PROFILE_PATH"
fi

echo "Initializing database at $DB_PATH ..."

sqlite3 "$DB_PATH" <<'SQL'
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- Expense categories
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT DEFAULT '',
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Expense sources (where money goes)
CREATE TABLE IF NOT EXISTS expense_sources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT DEFAULT 'vendor',
    category_id INTEGER REFERENCES categories(id),
    estimated_amount REAL DEFAULT 0,
    frequency TEXT DEFAULT 'one-time',
    notes TEXT DEFAULT '',
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Recurrent expenses
CREATE TABLE IF NOT EXISTS recurrent_expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id INTEGER REFERENCES expense_sources(id),
    name TEXT NOT NULL,
    amount REAL NOT NULL,
    frequency TEXT NOT NULL CHECK(frequency IN ('weekly','biweekly','monthly','quarterly','annually')),
    next_due_date TEXT,
    category_id INTEGER REFERENCES categories(id),
    active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Individual expense records
CREATE TABLE IF NOT EXISTS expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    amount REAL NOT NULL,
    date TEXT NOT NULL,
    vendor TEXT DEFAULT '',
    description TEXT DEFAULT '',
    category_id INTEGER REFERENCES categories(id),
    source_id INTEGER REFERENCES expense_sources(id),
    recurrent_id INTEGER REFERENCES recurrent_expenses(id),
    receipt_path TEXT DEFAULT '',
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Stored credentials for Phase 3 auto-fetch
CREATE TABLE IF NOT EXISTS credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    platform TEXT UNIQUE NOT NULL,
    credential_type TEXT DEFAULT 'api_key',
    credential_value TEXT NOT NULL,
    notes TEXT DEFAULT '',
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- OpenRouter ledger (synced API spending)
CREATE TABLE IF NOT EXISTS openrouter_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    api_key_label TEXT DEFAULT '',
    date TEXT NOT NULL,
    usage_daily REAL DEFAULT 0,
    usage_weekly REAL DEFAULT 0,
    usage_monthly REAL DEFAULT 0,
    usage_total REAL DEFAULT 0,
    credit_limit REAL,
    limit_remaining REAL,
    is_free_tier INTEGER DEFAULT 0,
    synced_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    raw_hash TEXT,
    UNIQUE(api_key_label, date, raw_hash)
);

-- Income / revenue records
CREATE TABLE IF NOT EXISTS income (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    amount REAL NOT NULL,
    date TEXT NOT NULL,
    source TEXT DEFAULT '',
    description TEXT DEFAULT '',
    category TEXT DEFAULT 'Revenue',
    recurring INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Generated reports log
CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    period TEXT NOT NULL,
    format TEXT DEFAULT 'summary',
    file_path TEXT,
    generated_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

-- Seed default categories
INSERT OR IGNORE INTO categories (name, description) VALUES
    ('Payroll', 'Employee salaries, contractor payments, bonuses'),
    ('SaaS/API', 'Software subscriptions and API usage fees'),
    ('Infrastructure', 'Cloud hosting, servers, domains, CDN'),
    ('Office', 'Rent, supplies, equipment, furniture'),
    ('Travel', 'Flights, hotels, transportation, meals'),
    ('Marketing', 'Ads, content creation, PR, events'),
    ('Legal', 'Lawyers, licenses, insurance, compliance'),
    ('Misc', 'Uncategorized or one-off expenses');
SQL

echo "Database initialized successfully."
echo "Tables: categories, expense_sources, recurrent_expenses, expenses, credentials, openrouter_ledger, reports"
echo "Default categories seeded (8 categories)."
echo ""
echo "DB location: $DB_PATH"
echo "Scripts:     $SCRIPTS_DIR/"
echo "Reports:     $REPORTS_DIR/"
