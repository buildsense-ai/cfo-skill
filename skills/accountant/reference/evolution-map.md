---
name: evolution-map
description: 3-phase evolution system for the accountant agent
---

# Evolution Map — Accountant Agent Phases

The accountant agent evolves through 3 phases based on how much it knows about the user's
financial landscape. Phase transitions are automatic, determined by database state.

**Critical rule**: At the start of every conversation, read the JSON profile first:
```bash
bash ~/.accountant/scripts/manage-profile.sh read
```
This gives you the user's known state before doing anything. After learning new info, update JSON immediately.

## Phase 1: Onboarding (探索期)

**Trigger**: `expense_sources < 3` OR `recurrent_expenses = 0`

**Agent behavior**:
- Proactively asks about every major expense category
- Confirms what the user does NOT have (negative confirmation is critical)
- Probes for recurrence patterns on every expense mentioned
- Builds the initial expense source map

**Key questions to ask**:

```
Category Sweep (ask one by one, don't dump all at once):
1. "What SaaS tools or API services does your company pay for?"
2. "Do you have payroll? How many people, roughly what frequency?"
3. "Any cloud infrastructure costs — AWS, GCP, Azure, Vercel, etc.?"
4. "Office-related expenses — rent, supplies, equipment?"
5. "Travel or entertainment expenses?"
6. "Marketing spend — ads, content, tools?"
7. "Legal or compliance costs — lawyers, licenses, insurance?"
8. "Any other regular expenses I should know about?"
```

**Recurrence probing** (for each expense):
```
- "Is this a one-time or recurring expense?"
- "How often? Weekly / monthly / quarterly / annually?"
- "Roughly how much each time?"
- "Where does this charge show up? Credit card? Bank transfer? Platform invoice?"
```

**Negative confirmation** (critical for completeness):
```
- "Just to make sure — you don't currently have any [X] expenses, right?"
- "No outstanding loans or debt payments?"
- "No pending invoices from vendors?"
```

**Data written in Phase 1**:
- **JSON profile** (update immediately after each answer):
  - `expense_landscape.known_sources`: each discovered expense source
  - `expense_landscape.confirmed_absent`: categories user confirmed they don't have
  - `recurrents`: confirmed recurring expense patterns
  - `onboarding_progress.categories_asked`: track which categories have been covered
  - `onboarding_progress.categories_remaining`: what's left to ask
- **SQLite** (structured data):
  - `expense_sources`: each source with name, type, category, estimated_amount, frequency
  - `recurrent_expenses`: confirmed recurring items with amount, frequency, next_due
  - `categories`: any custom categories the user mentions

### Phase 1 Exit Criteria
- At least 3 expense sources logged
- At least 1 recurrent expense confirmed
- User has been asked about all 8 default categories

---

## Phase 2: Pattern-Aware (熟悉期)

**Trigger**: `expense_sources >= 3` AND `recurrent_expenses >= 1` AND `credentials = 0`

**Agent behavior**:
- Reads JSON profile first — checks `known_sources` and `confirmed_absent` before asking anything
- Knows the user's expense landscape — stops asking about known categories
- Only asks about NEW or UNUSUAL expenses
- Flags anomalies against historical patterns
- Suggests category refinements
- Can remind user about upcoming recurrent expenses
- Updates JSON profile when new sources are discovered or existing ones change

**Anomaly detection rules**:
```sql
-- Flag if current month spend in a category exceeds 1.5x the 3-month average
SELECT c.name,
       SUM(CASE WHEN e.date >= date('now','start of month') THEN e.amount ELSE 0 END) as current,
       AVG(monthly_total) as avg_3mo
FROM expenses e
JOIN categories c ON e.category_id = c.id
WHERE e.date >= date('now','-3 months')
GROUP BY c.id
HAVING current > avg_3mo * 1.5;
```

**Recurrence tracking**:
```sql
-- Find recurrent expenses due in the next 7 days
SELECT name, amount, frequency, next_due_date
FROM recurrent_expenses
WHERE next_due_date BETWEEN date('now') AND date('now','+7 days')
ORDER BY next_due_date;
```

**What to ask vs. what to skip**:
- SKIP: Known recurrents (just log them when due)
- ASK: New vendors not in expense_sources
- ASK: Amounts that deviate >30% from historical
- SUGGEST: "Your [category] spending is trending up. Want to set a budget alert?"

### Phase 2 Exit Criteria
- At least 5 expense sources logged
- At least 1 credential stored (user trusts agent enough to share access)

---

## Phase 3: Autonomous (自主期)

**Trigger**: `credentials >= 1` AND `expense_sources >= 5`

**Agent behavior**:
- JSON profile is the authoritative source for platform access info and credential refs
- Auto-fetches data from platforms using stored credentials via `auto-fetch.sh`
- Proactively generates balance sheets and reports without being asked
- Auto-categorizes new expenses based on learned vendor patterns
- Sends budget alerts when thresholds are breached
- Can reconcile data across multiple sources

**Auto-fetch automation**:
```bash
# Run full auto-fetch cycle
bash ~/.accountant/scripts/auto-fetch.sh

# Preview what would be fetched
bash ~/.accountant/scripts/auto-fetch.sh --dry-run
```

**Auto-fetch capabilities**:
- OpenRouter: API key -> sync spending via `/api/v1/key`
- Bank statements: If user provides CSV/PDF export path, auto-process
- Platform dashboards: If credentials stored, can describe how to check

**Proactive behaviors**:
```
- Weekly: "Here's your weekly spending summary: [report]"
- Monthly: "Month-end report ready. Total: $X. Top category: [Y]."
- On anomaly: "Alert: [category] spending spiked 2.3x this week."
- On recurrent due: "Reminder: [expense] ($X) is due in 3 days."
```

**Vendor pattern learning**:
```sql
-- Learn category from vendor history
SELECT vendor, category_id, COUNT(*) as freq
FROM expenses
WHERE vendor = ?
GROUP BY category_id
ORDER BY freq DESC
LIMIT 1;
```

When a new expense comes in from a known vendor, auto-assign the most frequent category
and just confirm with user: "Logged $X from [vendor] under [category]. Correct?"

---

## Phase Detection SQL

Run this to determine current phase:

```sql
SELECT
  (SELECT COUNT(*) FROM expense_sources) as source_count,
  (SELECT COUNT(*) FROM recurrent_expenses) as recurrent_count,
  (SELECT COUNT(*) FROM credentials) as credential_count,
  CASE
    WHEN (SELECT COUNT(*) FROM expense_sources) < 3
         OR (SELECT COUNT(*) FROM recurrent_expenses) = 0
    THEN 1
    WHEN (SELECT COUNT(*) FROM credentials) = 0
    THEN 2
    ELSE 3
  END as current_phase;
```

---

## Evolution Visualization

```
Phase 1 (Onboarding)          Phase 2 (Pattern-Aware)       Phase 3 (Autonomous)
┌─────────────────────┐       ┌─────────────────────┐       ┌─────────────────────┐
│ Ask everything      │       │ Ask only new items   │       │ Auto-fetch & report  │
│ Confirm recurrents  │──────>│ Flag anomalies       │──────>│ Auto-categorize      │
│ Build source map    │       │ Suggest optimizations│       │ Proactive alerts     │
│ Negative confirm    │       │ Track due dates      │       │ Reconcile sources    │
└─────────────────────┘       └─────────────────────┘       └─────────────────────┘
   sources < 3                   sources >= 3                  credentials >= 1
   recurrents = 0                credentials = 0               sources >= 5
```
