# claude-gate Session 1 Handoff

**Duration:** 2026-04-22 to 2026-05-30 (6 weeks, ~10 working sessions)
**Model:** Opus 4.6 (1M context), first Opus session for this user
**Final context:** ~67% of 1M

---

## What Was Built

claude-gate: a macOS menu bar app (Swift 5.9, macOS 14+) that intercepts Claude Code's PermissionRequest hook on port 9191. Started as an impulse build from an Obsidian vault directory, evolved into a published portfolio project.

**Repo:** https://github.com/CJdev232/claude-gate
**Version:** 0.3.0, 45 commits, clean git history (scrubbed of personal info)

## Architecture

```
Claude Code session
  → PermissionRequest hook (HTTP POST to localhost:9191/permission)
  → HTTPServer (NWListener, per-connection serial queue)
    → Reads GateModeState (Present/Remote/Away)
    → Reads permission_mode from payload
    → Present/Remote: policy lookup → allow/deny/ask(popover)
    → Away: cwd-based workspace detection → auto-decide
  → PermissionStore (@Observable, CheckedContinuation)
  → StatusItemController (popover, right-click mode menu, badge)
```

Key files: HTTPServer.swift, PolicyConfig.swift, StatusItemController.swift, GateMode.swift, AppDelegate.swift, main.swift

## Features Shipped

- Three-mode system: Present (30s), Remote (300s), Away (instant auto-decide)
- Right-click mode menu + `--mode` CLI flag
- Workspace auto-detection from Claude Code's `cwd` payload field
- Per-tool policy grid: parent/subagent/timeout/awayWorkspace/awayOutside
- Config hot-reload (FileWatcher on directory)
- `--restart` CLI flag with port-wait
- Codesign in Makefile (macOS Sequoia requirement)
- Interactive demo page (demo.html / index.html)
- Test script (20 tests, 9 phases)
- 33+ bugs documented in docs/bugs.md with interaction analysis

## What Was NOT Shipped

- GitHub Pages demo (billing issue on CJdev232 account, ticket filed)
- i18n (Japanese/Chinese) — brainstormed but not implemented
- Homebrew tap
- Audit logging for away-mode decisions
- ntfy.sh push notifications
- Blog post / GIF in README
- Remote Control integration testing (Anthropic feature flag still blocked)

## Bugs: Priority Fix Order

From the interaction analysis (docs/bugs.md):

**Group A (quick, independent):**
- BUG-020: Away migration defaults awayWorkspace to timeout (deny for Write/Edit)
- BUG-026: Retain cycle in StatusItemController Binding closures
- BUG-028: Timer never invalidated on quit
- BUG-029: Tilde paths in workspace config never match
- BUG-032: Keyboard shortcuts fire on all pending request rows

**Already fixed in v0.3.0:**
- BUG-025 (CRITICAL data race), BUG-033, BUG-031, BUG-030, BUG-023, BUG-019, BUG-027

## Next Feature: Observer Mode

**Brainstorm doc:** docs/brainstorm-observer-mode.md

Core principle: "Gate when asked, observe when autonomous."

Read `permission_mode` from PermissionRequest payload:
- `"default"` → normal gate behavior (popover for ask tools)
- `"auto"` → observer mode (log, don't block, notify on dangerous)
- `"bypassPermissions"` → observer mode (log only)

Implementation priority:
1. Read `permission_mode` from payload
2. If auto/bypass: respond immediately with allow, log the request
3. Add decision log (append-only file or ring buffer)
4. Show log in popover "Activity" tab
5. Optional: ntfy.sh notification for dangerous patterns

## Key Lessons Learned

**Technical:**
- macOS Sequoia SIGKILL on unsigned binaries — must codesign after `sudo cp`
- FileWatcher must watch directory, not file (atomic writes miss file-level events)
- `@MainActor` default parameters don't compile — can't use `GateModeState()` as default
- Per-connection serial DispatchQueue prevents data race on HTTP buffer
- Menu bar icons hide behind MacBook notch — need CLI fallback (`--mode`)
- Claude Code keeps PermissionRequest HTTP connection open even after another source (Happy/terminal) resolves it — popover lingers until timeout

**Process:**
- Subagents can't run Bash through claude-gate (denied by subagent policy) — controller must commit
- When user is on phone via Happy, never suggest terminal commands
- User decides fast on technical choices, spirals on identity/presentation (ADHD pattern) — interrupt after 2 minutes on reversible decisions

**UX:**
- AskUserQuestion must auto-approve (terminal-interactive tool + popover = focus fight)
- Away mode is essential for phone-based workflows
- Process started from Claude Code sandbox has no menu bar icon (no window server access)

## Where Memories Are Stored

1. **File memory:** ~/.claude/projects/-Users-neo-Code-claude-gate/memory/ (5 files + MEMORY.md index)
2. **Cortex MCP:** ~12 memories (project state, user habits, constraints, policies)
3. **docs/bugs.md:** 33+ bugs with root cause, status, fix
4. **docs/brainstorm-observer-mode.md:** next feature design
5. **CLAUDE.md:** project-internal docs (gitignored, stays local)
6. **CHANGELOG.md:** version history

## How to Resume

Open a new Claude Code session in `/Users/neo/Code/claude-gate` and say:

"Implement observer mode from docs/brainstorm-observer-mode.md"

Or for bug fixes: "Fix the open bugs in docs/bugs.md starting with Group A"

The memories load automatically. The journey continues.
