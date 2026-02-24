---
name: data-architecture
description: JSON metadata vs SQLite data store — separation of concerns
---

# Data Architecture — JSON + SQLite Split

## Two-Layer Design

```
~/.accountant/
├── user-profile.json    ← WHO the user is, WHAT they have, WHERE to look
├── accountant.db        ← HOW MUCH, actual transactions, balances
├── scripts/
└── reports/
```

## Layer 1: JSON Metadata (`user-profile.json`)

The JSON file is the agent's "memory" of the user's financial landscape.
It answers: "What do I know about this user before doing anything?"

**Read this file FIRST at the start of every conversation.**

### Structure

```json
{
  "company": { ... },           // Who is this company
  "expense_landscape": {
    "known_sources": [...],     // All known expense sources
    "confirmed_absent": [...],  // Categories user confirmed they DON'T have
    "custom_categories": [...]  // User-defined categories beyond defaults
  },
  "recurrents": [...],          // Recurring expense patterns
  "income_sources": [...],      // Revenue streams
  "data_access": {
    "platforms": [...],         // Where to fetch data (with credential refs)
    "bank_accounts": [...],     // Bank account info for reconciliation
    "invoice_locations": [...]  // Where invoices/receipts live
  },
  "preferences": { ... },      // User preferences
  "onboarding_progress": { ... } // What's been asked, what remains
}
```

### known_sources entry format

```json
{
  "name": "OpenRouter",
  "category": "SaaS/API",
  "estimated_monthly": 150.00,
  "frequency": "monthly",
  "how_to_check": "API call with key, or dashboard at openrouter.ai",
  "credential_ref": "openrouter",
  "notes": "Main AI API provider"
}
```

### recurrents entry format

```json
{
  "name": "AWS EC2",
  "amount": 200.00,
  "frequency": "monthly",
  "category": "Infrastructure",
  "due_day": 1,
  "auto_fetch": true,
  "notes": "us-east-1 production servers"
}
```

### income_sources entry format

```json
{
  "name": "Product Revenue",
  "type": "recurring",
  "estimated_monthly": 5000.00,
  "frequency": "monthly",
  "notes": "SaaS subscription revenue"
}
```

### data_access.platforms entry format

```json
{
  "platform": "openrouter",
  "credential_type": "api_key",
  "credential_stored": true,
  "fetch_method": "api",
  "api_endpoint": "https://openrouter.ai/api/v1/key",
  "notes": ""
}
```

### CRUD Operations

Use `scripts/manage-profile.sh` for all JSON operations:

```bash
# Read entire profile
bash ~/.accountant/scripts/manage-profile.sh read

# Read a specific section
bash ~/.accountant/scripts/manage-profile.sh get "company"
bash ~/.accountant/scripts/manage-profile.sh get "expense_landscape.known_sources"

# Update a section (merges with existing)
bash ~/.accountant/scripts/manage-profile.sh set "company.name" "Acme Corp"

# Add to an array
bash ~/.accountant/scripts/manage-profile.sh add "expense_landscape.known_sources" '{"name":"AWS","category":"Infrastructure"}'

# Remove from an array by name
bash ~/.accountant/scripts/manage-profile.sh remove "expense_landscape.known_sources" "AWS"

# Move a category to confirmed_absent
bash ~/.accountant/scripts/manage-profile.sh add "expense_landscape.confirmed_absent" "Travel"
```

---

## Layer 2: SQLite Data Store (`accountant.db`)

The database stores actual financial numbers — every transaction, every sync, every balance.

### Key Tables

| Table | Purpose |
|-------|---------|
| `expenses` | Individual expense transactions (outflow) |
| `income` | Individual income transactions (inflow) |
| `categories` | Expense/income category definitions |
| `expense_sources` | Where expenses come from |
| `recurrent_expenses` | Recurring expense definitions |
| `credentials` | Platform credentials (API keys, passwords) |
| `openrouter_ledger` | Synced OpenRouter API usage data |
| `reports` | Generated report log |

### Credentials Table

Credentials are stored in SQLite (not JSON) for security isolation:

```sql
SELECT platform, credential_type, credential_value FROM credentials;
-- platform: "openrouter", "aws", "stripe", etc.
-- credential_type: "api_key", "password", "token"
-- credential_value: the actual secret (plaintext for now)
```

The JSON `data_access.platforms[].credential_stored` flag just says "yes, a credential exists" —
the actual secret lives only in SQLite.

---

## Data Flow

```
User tells agent info          Agent fetches data           Agent computes
        │                              │                          │
        ▼                              ▼                          ▼
  user-profile.json              accountant.db              accountant.db
  (metadata/context)           (raw transactions)         (balance sheet)
        │                              │                          │
        └──────────────────────────────┴──────────────────────────┘
                                       │
                                  Agent reads both
                              at start of conversation
```

### Rule: Always Read JSON First

Before any action, the agent should:
1. `bash ~/.accountant/scripts/manage-profile.sh read` — understand user context
2. Then decide what to do based on known state
3. After learning new info, update JSON immediately
