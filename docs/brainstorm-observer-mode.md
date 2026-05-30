# claude-gate: Observer Mode Brainstorm

**Date:** 2026-05-30
**Goal:** Evolve claude-gate to coexist with Claude Code's Auto Mode, /goal, /dream, and Agent View without interfering with autonomous workflows.

## Core Principle

**Gate when asked, observe when autonomous.**

## Design

claude-gate reads `permission_mode` from the PermissionRequest payload and adapts:

| `permission_mode` | claude-gate behavior |
|---|---|
| `"default"` | Normal — use policy grid, show popover for `ask` tools |
| `"auto"` | Observer mode — log decisions, don't block. Show in dashboard. Alert on dangerous actions via notification. |
| `"bypassPermissions"` | Observer mode — log only, never block |

## Observer Mode Behavior

- See every request flowing through, log it with timestamp/tool/path/decision
- Show stats in menu bar badge (requests/min, allowed/denied counts)
- Never hold the HTTP connection open — respond immediately with allow
- If something looks dangerous (write outside workspace, destructive Bash pattern), send notification (ntfy.sh or Happy) instead of blocking
- Dashboard viewable in popover: scrollable log of recent decisions

## Three-Mode System Evolution

| Mode | default permission_mode | auto/bypass permission_mode |
|------|------------------------|----------------------------|
| Present | Popover for ask tools (current) | Observer dashboard |
| Remote | Popover with 5min timeout | Observer + phone notifications |
| Away | Auto-decide by workspace | Observer (already autonomous) |

## Implementation Priority

1. Read `permission_mode` from payload (already available in JSON)
2. If auto/bypass: respond immediately with allow, log the request
3. Add a decision log (append-only local file or in-memory ring buffer)
4. Show log in popover's new "Activity" tab
5. Optional: ntfy.sh notification for dangerous patterns

## What This Enables

- `/goal` runs for hours uninterrupted — claude-gate watches silently
- Auto Mode makes its own decisions — claude-gate provides transparency
- User checks the activity log when back at desk
- Phone notification if something unexpected happens (write to /etc, rm -rf, etc.)
