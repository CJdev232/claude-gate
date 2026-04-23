# Changelog

## [0.3.0.0] - 2026-04-23

### Fixed
- CRITICAL: Pin each HTTP connection to a serial dispatch queue, preventing data race on buffer (BUG-025)
- Handle .cancelled state in listener startup continuation, preventing dangling async caller (BUG-033)
- Throw on corrupt settings.json instead of silently overwriting user settings (BUG-031)
- Safe optional chaining in PolicyGridView Binding closures, preventing crash on hot-reload (BUG-030)
- Read port from config in all locations, removing hardcoded 9191 in subagent hooks, kill-retry, and installer (BUG-019, BUG-027)
- Widen MenuBarView to 400px to fit 6-column policy grid without clipping (BUG-023)
- Test script detects existing claude-gate instance before launching, avoiding port-in-use alert

## [0.2.0.0] - 2026-04-23

### Added
- Three-mode system (Present/Remote/Away) via right-click context menu
- Away mode with workspace-scoped auto-approve policies
- Auto-detect workspace from Claude Code session cwd
- remote_timeout config for phone-based decisions (default 300s)
- Away policy columns in popover policy grid (two-state toggle)
- --restart CLI flag for clean process restart with port-wait
- Unified logging via os.Logger (subsystem com.claude-gate)
- Port-in-use detection on startup with kill-and-retry alert
- Auto-restart NWListener on post-startup failure
- Auto-deny orphaned requests when connection drops

### Fixed
- AskUserQuestion auto-approved to prevent focus-stealing bug
- Popover no longer steals focus from iTerm2 hotkey window
- Popover uses .applicationDefined behavior to prevent auto-dismiss
- HTTP parser accumulates reads for large payloads (was 64KB limit)
- LaunchAgent: KeepAlive, log paths, launchctl bootstrap
- FileWatcher watches directory instead of file (catches atomic writes)
- Port read from config in --restart instead of hardcoded 9191

## [0.1.0.0] - 2026-04-19

### Added
- macOS menu bar app intercepting Claude Code PermissionRequest hook
- HTTP server on port 9191 with NWListener
- SwiftUI popover with approve/deny buttons and keyboard shortcuts
- Per-tool policy config for parent and subagent sessions
- Policy grid UI with click-to-toggle cells
- Config hot-reload via FileWatcher
- Auto-open/close popover on request arrival/resolution
- Badge count on menu bar icon
- --install/--uninstall CLI for hook registration
- Subagent tracking via hooks
- Timeout policy per tool
