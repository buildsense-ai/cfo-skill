---
name: openrouter-integration
description: OpenRouter API integration for spending queries and sync
---

# OpenRouter Integration

## Overview

OpenRouter exposes a `/api/v1/key` endpoint that returns usage stats for any API key.
This is the primary data source for API spending tracking.

## API Endpoint

```
GET https://openrouter.ai/api/v1/key
Authorization: Bearer <OPENROUTER_API_KEY>
```

### Response Format

```json
{
  "data": {
    "label": "my-key-label",
    "limit": 100.0,
    "limit_remaining": 75.50,
    "usage": 24.50,
    "usage_daily": 3.20,
    "usage_weekly": 18.40,
    "usage_monthly": 24.50,
    "is_free_tier": false
  }
}
```

### Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `label` | string | User-assigned key label |
| `limit` | float | Credit limit (null = unlimited) |
| `limit_remaining` | float | Remaining credits |
| `usage` | float | Total lifetime usage in USD |
| `usage_daily` | float | Today's usage in USD |
| `usage_weekly` | float | This week's usage in USD |
| `usage_monthly` | float | This month's usage in USD |
| `is_free_tier` | bool | Whether this is a free-tier key |
