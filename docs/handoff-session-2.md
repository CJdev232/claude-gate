# claude-gate Session 2 Handoff

**Date:** 2026-05-30
**Duration:** ~4 hours (10:56 - 14:37 UTC+8), with a lunch break
**Model:** Opus 4.6 (1M context)
**Location:** Hotel in transit (hall → hotel room, no window)

---

## What Was Built

### Observer Mode v1
Core principle: "Gate when asked, observe when autonomous."

- Reads `permission_mode` from PermissionRequest payload
- `auto` / `bypassPermissions` → instant allow + log (no popover, no blocking)
- All decisions (gated + observed) logged to:
  - In-memory ring buffer (200 entries) for Activity tab UI
  - Append-only `~/.claude-gate/activity.jsonl` (unbounded for v1)

### Activity Tab
Third tab in popover alongside "Requests" and "Policies". Shows chronological list of all traffic with:
- `▲`/`▼` decision badges (teal allow / pink deny)
- "observer" pill for auto-allowed requests
- Timestamp, tool name, input preview

### Dangerous Pattern Detection
Observer mode doesn't block, but notifies on dangerous patterns:
- Destructive bash: `rm -rf`, `git push --force`, `git reset --hard`, `DROP TABLE`
- System path writes: `/etc/`, `/usr/`, `~/.ssh/`
- Credential files: `.env`, `credentials.json`, SSH keys
- Writes outside workspace
- Notifications via macOS `osascript` + optional ntfy.sh (config: `server.ntfy_endpoint`)

### Observer Gate Modes
Two new modes in right-click menu + `--mode` CLI:
- **Observer**: auto-allow everything, log + notify
- **Observer (Workspace)**: auto-allow inside workspace, gate outside

### Bug Fixes
**AskUserQuestion passthrough** — was responding with `{"behavior": "allow"}` which told Claude Code the hook handled the permission, preventing the interactive UI from rendering. Fix: respond without `hookSpecificOutput` so Claude Code falls back to native handling.

**Group A (5 bugs):**
- BUG-020: `awayWorkspace` fallback to `.allow` instead of `timeout`
- BUG-026: `[weak self]` in Binding closures to break retain cycle
- BUG-028: Store refresh timer as property, invalidate on quit
- BUG-029: Expand tilde in workspace config paths
- BUG-032: Keyboard shortcuts only fire on first pending row

## Commits (on main, merged from feature/observer-mode)

```
c393cba Merge feature/observer-mode: observer mode v1 + bug fixes
ace32c9 fix: Group A bugs (020, 026, 028, 029, 032)
5220008 feat: observer and observer-workspace gate modes
842244a feat: dangerous pattern detection with macOS + ntfy notifications
f4dc62f fix: passthrough AskUserQuestion instead of hook-deciding it
8ae2258 feat: observer mode v1 — gate when asked, observe when autonomous
```

## Current State

- **Branch:** `main` at `c393cba` (6 commits ahead of origin, not pushed)
- **Running binary:** PID from `.build/release/claude-gate` (latest build with all fixes)
- **Mode:** Observer (Workspace) active
- **Binary location:** `.build/release/` — NOT installed to `/usr/local/bin` (needs sudo)
- **feature/observer-mode branch:** still exists, can be deleted

## New Files

| File | Purpose |
|------|---------|
| `Sources/ClaudeGateLib/ActivityLog.swift` | Ring buffer + JSONL dual-write activity log |
| `Sources/ClaudeGateLib/DangerDetector.swift` | Pattern matching + macOS/ntfy notifications |
| `Sources/ClaudeGateLib/Views/ActivityRowView.swift` | SwiftUI row for Activity tab |
| `scripts/test-observer.sh` | 7-test observer mode verification script |

## What Was NOT Done

- Push to origin
- Install binary to `/usr/local/bin`
- Update docs/bugs.md to mark Group A bugs as FIXED
- Activity log rotation (unbounded for v1)
- ntfy.sh integration testing with real endpoint
- Remaining open bugs (BUG-021, 022, 024, 027, 030, 031, 034)
- Activity tab features (filter, search, stats header)
- Visual UI testing of Activity tab / badge

## Key Lessons Learned

**Technical:**
- `UNUserNotificationCenter` crashes in non-bundled SwiftPM binaries (`bundleProxyForCurrentProcess is nil`). Use `osascript` for macOS notifications instead.
- PermissionRequest hook responding with `{"behavior": "allow"}` for AskUserQuestion prevents the interactive UI from rendering. Must respond without `hookSpecificOutput` for passthrough.
- Git worktrees as sibling directories (`../project-worktree`) fall outside Claude Code's sandbox write allowlist. Use `.claude/worktrees/` via `EnterWorktree` or `.worktrees/` inside the project.
- Claude Code's `EnterWorktree`/`ExitWorktree` tools handle worktree lifecycle automatically — prefer over manual `git worktree add`.
- `GateMode` enum with `rawValue` requires exact case matching — CLI `--mode` lowercases input, needs a mapping table.

**Process:**
- Observer (Workspace) mode is the sweet spot for development sessions — no popover interruption, but dangerous actions outside workspace still gated.
- For sequential feature work, same-directory branch > worktree. Worktrees are for parallel work across branches.
- The `swift build` command needs `dangerouslyDisableSandbox` in Claude Code due to sandbox_apply restrictions.

## How to Resume

```
cd ~/Code/claude-gate
```

Next actions (pick one):
- "Push to origin and install the binary" (ships observer mode)
- "Fix the remaining open bugs" (BUG-021, 022, 024, 027, 030, 031, 034)
- "Add activity log features" (filter, search, stats)
- "Test the UI visually" (click menu bar, check Activity tab)
