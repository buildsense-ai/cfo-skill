# Accountant

Company accountant skill for Claude Code. Tracks expenses and income, generates balance sheets, reads invoices/receipts, syncs OpenRouter API costs, and produces financial reports — all through natural conversation.

## Install

### Claude Code (one-line)

```bash
claude plugin install https://github.com/buildsense-ai/cfo-skill
```

### Manual (any agent)

```bash
git clone https://github.com/buildsense-ai/cfo-skill.git
cp -r cfo-skill/skills/accountant ~/.claude/skills/
```

Then add the skill's scripts to the runtime directory:

```bash
mkdir -p ~/.accountant
cp -r cfo-skill/skills/accountant/scripts ~/.accountant/
cp cfo-skill/skills/accountant/user-profile.json ~/.accountant/
```

## What It Does

- Track and categorize company expenses and income
- Read invoices, receipts, and bank statements (PDF/image)
- Query financial data via SQLite
- Sync OpenRouter API spending automatically
- Generate financial reports and balance sheets
- Evolves through 3 phases: Onboarding → Pattern-Aware → Autonomous

## Usage

Once installed, invoke with `/accountant` or Claude will auto-detect when you ask about expenses, budgets, invoices, or financial reports.

## Requirements

- Claude Code CLI
- `sqlite3`
- `python3`
- `pdftotext` (optional, for PDF invoice reading)
