---
name: expense-categories
description: Default expense category taxonomy for company accounting
---

# Expense Categories — Default Taxonomy

## Built-in Categories

These are pre-loaded into the `categories` table on first init.

| ID | Name | Description | Examples |
|----|------|-------------|----------|
| 1 | Payroll | Employee salaries, contractor payments, bonuses | Monthly salary, freelancer invoice |
| 2 | SaaS/API | Software subscriptions and API usage fees | OpenRouter, GitHub, Slack, AWS |
| 3 | Infrastructure | Cloud hosting, servers, domains, CDN | AWS EC2, Vercel, Cloudflare |
| 4 | Office | Rent, supplies, equipment, furniture | WeWork, printer ink, monitors |
| 5 | Travel | Flights, hotels, transportation, meals on trips | Business flights, Uber, hotels |
| 6 | Marketing | Ads, content creation, PR, events | Google Ads, conference sponsorship |
| 7 | Legal | Lawyers, licenses, insurance, compliance | Business license, liability insurance |
| 8 | Misc | Anything that doesn't fit above | Bank fees, one-off purchases |

## Category Rules

- Every expense MUST have a category
- If unsure, use `Misc` and ask user to confirm
- User can create custom categories at any time via:
  ```sql
  INSERT INTO categories (name, description) VALUES ('Custom Name', 'Description');
  ```
- Categories cannot be deleted if expenses reference them

## Auto-Categorization Patterns

When the agent reaches Phase 3, use vendor history to auto-assign:

```sql
-- Find most common category for a vendor
SELECT c.name, COUNT(*) as freq
FROM expenses e JOIN categories c ON e.category_id = c.id
WHERE e.vendor = :vendor
GROUP BY c.id ORDER BY freq DESC LIMIT 1;
```

Known vendor-to-category mappings (seed data):

| Vendor Pattern | Category |
|---------------|----------|
| `openrouter`, `anthropic`, `openai` | SaaS/API |
| `aws`, `gcp`, `azure`, `vercel`, `cloudflare` | Infrastructure |
| `google ads`, `facebook ads`, `meta ads` | Marketing |
| `wework`, `regus` | Office |
| `uber`, `lyft`, `airline`, `hotel` | Travel |
