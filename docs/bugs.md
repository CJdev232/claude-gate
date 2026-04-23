# claude-gate Bug Log

When encountering or solving a bug during development, note it here. This includes new discoveries, status changes, and fixes. The log compounds across sessions and prevents re-investigation of known issues.

## Format

```
### BUG-XXX: Title
- **Description**: What happens, how to reproduce
- **Root Cause**: Why it happens
- **Status**: FIXED | WORKAROUND | ENVIRONMENT | OPEN
- **Fix**: What was done or proposed
- **Discovered**: YYYY-MM-DD
```

---

### BUG-001: AskUserQuestion focus stealing
- **Description**: Popover repeatedly steals focus from terminal while AskUserQuestion waits for input. User can't select answers because the popover keeps reappearing.
- **Root Cause**: AskUserQuestion fires PermissionRequest hook. The 200ms timer re-triggers autoOpenIfNeeded() which calls activate(ignoringOtherApps:), stealing focus from the terminal where the selection UI is rendered.
- **Status**: FIXED
- **Fix**: Auto-approve AskUserQuestion in PolicyConfig.defaultConfig() (allow/allow/allow). Existing user configs need manual addition. Commit `4bf0f9a`.
- **Discovered**: 2026-04-22

### BUG-002: Popover steals focus from iTerm2 hotkey window
- **Description**: Every permission request causes iTerm2 hotkey window to disappear. User must press hotkey again to bring terminal back.
- **Root Cause**: autoOpenIfNeeded() calls NSApplication.shared.activate(ignoringOtherApps:true), which activates claude-gate's process, deactivating iTerm2. Hotkey windows auto-hide on focus loss.
- **Status**: FIXED
- **Fix**: Removed activate() call. After popover.show(), set window level to .floating so it appears above other windows without stealing focus. Commit `3254d35`.
- **Discovered**: 2026-04-22

### BUG-003: Popover auto-dismissed by macOS on re-activate
- **Description**: Popover opens for first permission request but auto-closes on the second. Subsequent requests show no popover.
- **Root Cause**: popover.behavior was .transient. macOS auto-dismisses transient popovers when it detects focus has moved, which happens on the second activate() call for a background menu bar app.
- **Status**: FIXED
- **Fix**: Changed to popover.behavior = .applicationDefined. Click monitor handles outside-click dismissal; autoCloseIfEmpty() handles empty-queue auto-close. Commit `3254d35`.
- **Discovered**: 2026-04-20

### BUG-004: HTTP parser truncates large payloads
- **Description**: POST bodies larger than 64KB are silently truncated. JSON parsing fails and the request is denied with "bad_request".
- **Root Cause**: Single conn.receive(maximumLength: 65_536) call. If Claude Code sends a large tool_input (e.g. Bash with long script), the body exceeds one read.
- **Status**: FIXED
- **Fix**: Accumulating reader that parses Content-Length from headers and keeps calling receive() until full body arrives. Max 1MB. Commit `5cd8896`.
- **Discovered**: 2026-04-22

### BUG-005: LaunchAgent fails to load with I/O error
- **Description**: claude-gate --install registers a LaunchAgent but launchctl load fails. User must start claude-gate manually.
- **Root Cause**: Three issues: (1) no StandardOutPath/StandardErrorPath in plist, (2) uses deprecated launchctl load instead of bootstrap, (3) no KeepAlive for crash recovery.
- **Status**: FIXED
- **Fix**: Added log paths (absolute, not ~), KeepAlive: true, ProcessType: Interactive, switched to launchctl bootstrap/bootout. Commit `793e51e`.
- **Discovered**: 2026-04-20

### BUG-006: Port-in-use silent failure
- **Description**: If a stale claude-gate process holds port 9191, new instance fails silently. Menu bar icon appears but no requests are processed.
- **Root Cause**: NWListener.start() throws on EADDRINUSE but the error was only logged with NSLog (no visible UI).
- **Status**: FIXED
- **Fix**: Show NSAlert offering to kill stale process and retry. Commit `5a8fa6a`.
- **Discovered**: 2026-04-22

### BUG-007: NWListener crash with no recovery
- **Description**: If NWListener enters .failed state after startup (e.g. network stack reset), the server silently dies. No requests processed until manual restart.
- **Root Cause**: The stateUpdateHandler from withCheckedThrowingContinuation is consumed on initial startup and not replaced with a persistent handler.
- **Status**: FIXED
- **Fix**: Install persistent stateUpdateHandler after startup. On .failed, attempt one restart after 1s delay. If restart also fails, KeepAlive LaunchAgent restarts the process. Commit `4c7be3e`.
- **Discovered**: 2026-04-22

### BUG-008: Orphaned continuations leak
- **Description**: If Claude Code drops the connection (timeout, network glitch) before user decides, the CheckedContinuation is never resumed. Pending request stays in UI forever.
- **Root Cause**: No connection state monitoring. The continuation is created in askUser() but nothing watches for connection death.
- **Status**: FIXED
- **Fix**: Install stateUpdateHandler on connection. On .cancelled/.failed, auto-deny the associated pending request (resume continuation with .deny). Safe for double-calls since PermissionStore.decide guards with firstIndex. Commit `20ff719`.
- **Discovered**: 2026-04-22

### BUG-009: FileWatcher misses atomic writes
- **Description**: Editing ~/.claude-gate/config.json with tools that do atomic writes (write temp file, rename into place) doesn't trigger config hot-reload.
- **Root Cause**: FileWatcher opens a file descriptor on config.json with O_EVTONLY. Atomic writes create a new inode; the old fd still points to the deleted inode and never receives events.
- **Status**: FIXED
- **Fix**: Watch the directory (~/.claude-gate/) instead of the file. Any directory change triggers a reload. Commit `20ff93c`.
- **Discovered**: 2026-04-22

### BUG-010: AskUserQuestion config not hot-reloaded
- **Description**: Added AskUserQuestion to defaultConfig() but existing user config at ~/.claude-gate/config.json doesn't include it. Auto-approve doesn't take effect until user manually edits config or deletes it.
- **Root Cause**: defaultConfig() only applies when no config file exists. Existing configs use the stored values. Config migration doesn't add new tool entries.
- **Status**: WORKAROUND
- **Fix**: Manually add AskUserQuestion to ~/.claude-gate/config.json. Could consider: on load, merge missing tools from defaultConfig() into loaded config. Not implemented yet.
- **Discovered**: 2026-04-22

### BUG-011: Menu bar icon hidden by macOS overflow
- **Description**: claude-gate icon not visible in menu bar. Process is running, server is listening, but no UI. Appears as if the app isn't running.
- **Root Cause**: macOS silently hides menu bar items when there's not enough space. Other apps (Warp, etc.) consume the available space. No error, no log, no crash.
- **Status**: ENVIRONMENT
- **Fix**: Quit unused menu bar apps to free space. Consider adding a --status CLI flag that reports process state independently of UI. Not fixable in code.
- **Discovered**: 2026-04-22

### BUG-012: Process restart timing race
- **Description**: `kill $(pgrep claude-gate) && claude-gate &` starts new process before old one releases port 9191. New process fails on EADDRINUSE.
- **Root Cause**: kill sends SIGTERM and returns immediately. Port release is async. The && chains to the next command before the port is free.
- **Status**: FIXED
- **Fix**: Added --restart CLI flag that kills old process, waits for port to be free (polling lsof, max 5 seconds), then starts new instance. Reads port from config. Commit `8de0dee`.
- **Discovered**: 2026-04-22

### BUG-013: Remote Control "not enabled" error
- **Description**: `claude remote-control` returns "Remote Control is not yet enabled for your account" despite being on a paid plan.
- **Root Cause**: Stale Statsig feature flag cache. DISABLE_TELEMETRY=1 in settings.json blocked Statsig refresh, freezing the tengu_ccr_bridge flag at "disabled". Even after removing the setting, cached evaluations persist.
- **Status**: ENVIRONMENT
- **Fix**: Delete ~/.claude/statsig/statsig.* files and restart Claude Code. If still failing, it's a server-side feature flag issue (Anthropic backend). See GitHub issues #28777, #38488.
- **Discovered**: 2026-04-22

### BUG-014: Code signing SIGKILL on macOS Sequoia
- **Description**: After `sudo cp .build/release/claude-gate /usr/local/bin/claude-gate`, the binary is immediately killed on launch with SIGKILL. No error output.
- **Root Cause**: macOS Sequoia (15.5) enforces code signature validation. The cp command invalidates the ad-hoc signature from swift build. The kernel kills the process before main() runs. Crash report shows: termination namespace=CODESIGNING, indicator="Invalid Page".
- **Status**: FIXED
- **Fix**: Added `codesign --force --sign - $(INSTALL_TO)` to Makefile install target. Ad-hoc re-signing after copy. Also added `make restart` convenience target. Commit pending (Bash denied in away mode during session).
- **Discovered**: 2026-04-23

### BUG-015: Away mode denies workspace writes unexpectedly
- **Description**: Switching to Away mode auto-denies Write/Edit inside workspace, even though the intent is to let Claude keep working on project files.
- **Root Cause**: Config migration defaults awayWorkspace to the timeout value (deny for Write/Edit). The defaultConfig() sets awayWorkspace to allow, but existing configs use migration fallback.
- **Status**: FIXED
- **Fix**: Manually added away_workspace/away_outside fields to ~/.claude-gate/config.json. Migration logic kept conservative (safe default). Users must configure explicitly or use defaultConfig() on fresh install.
- **Discovered**: 2026-04-23

### BUG-016: Subagent Bash denied by claude-gate
- **Description**: Subagents dispatched to implement code changes can't run swift build or git commit because claude-gate's policy denies Bash for subagents.
- **Root Cause**: Default policy has Bash subagent=deny. Subagents run as separate sessions and are tracked by SubagentTracker. Their Bash calls are correctly identified as subagent context and denied.
- **Status**: WORKAROUND
- **Fix**: Controller (main session) handles build and commit operations manually after subagent completes code changes. Alternatively, temporarily set Bash subagent=allow in config during implementation sessions.
- **Discovered**: 2026-04-22

### BUG-017: Process started from sandbox has no menu bar
- **Description**: Starting claude-gate from Claude Code's sandboxed Bash creates a process that runs (PID exists, port open) but no menu bar icon appears.
- **Root Cause**: Processes started from Claude Code's sandbox don't have access to the macOS window server. NSStatusBar.system.statusItem() silently fails. The HTTP server works but the GUI doesn't.
- **Status**: ENVIRONMENT
- **Fix**: Start claude-gate from a normal terminal session (not Claude Code's Bash). The --restart flag starts a child process that inherits the terminal's window server access.
- **Discovered**: 2026-04-22

### BUG-018: WebFetch and WebSearch bypass PermissionRequest hook
- **Description**: WebFetch and WebSearch calls never reach claude-gate. They auto-proceed silently with no popover and no log entry. They appear in the policy grid, giving a false impression they are gated.
- **Root Cause**: The PermissionRequest hook only fires for tools in `permissions.ask`. WebFetch/WebSearch are in `permissions.ask` in settings.json but Claude Code may handle them differently, or the hook doesn't fire for read-only network operations.
- **Status**: OPEN
- **Fix**: Either add a PreToolUse hook matcher for these tools, or remove them from the policy grid to avoid misleading UI.
- **Discovered**: 2026-04-22

### BUG-019: Port 9191 hardcoded in subagent hooks and installer
- **Description**: Changing `server.port` in config.json does not update the subagent POST URL in main.swift or the hook URL registered by --install. Subagent tracking and permission hooks silently break.
- **Root Cause**: main.swift line 35 hardcodes `http://127.0.0.1:9191`. Installer.swift line 59 hardcodes the same URL in the PermissionRequest hook registration. Only the HTTP server reads the configured port.
- **Status**: OPEN
- **Fix**: Load config in the subagent path and use config.server.port. The --install command should write the configured port into the hook URL in settings.json.
- **Discovered**: 2026-04-23

### BUG-020: Migration defaults awayWorkspace to timeout (code defect)
- **Description**: BUG-015 noted the symptom (away mode denies workspace writes). The underlying code defect: ToolPolicy.init(from:) falls back awayWorkspace to the timeout value, which is deny for Write/Edit. defaultConfig() sets awayWorkspace to allow, but existing configs never get this.
- **Root Cause**: PolicyConfig.swift line 34: `awayWorkspace = try c.decodeIfPresent(...) ?? timeout`. For Write (timeout=deny), this makes awayWorkspace=deny — opposite of the intended default.
- **Status**: WORKAROUND
- **Fix**: Manually add away_workspace to config. A proper fix would merge missing away fields from defaultConfig() on load, or change the fallback to .allow. Risk: changing fallback to .allow would also make Bash awayWorkspace=allow, which is unsafe. Needs per-tool logic or explicit migration.
- **Discovered**: 2026-04-23

### BUG-021: SubagentTracker entries never cleaned up
- **Description**: If a subagent session crashes or is killed without sending SubagentStop, the session ID stays in SubagentTracker forever. Future requests from any session with that ID get the more restrictive subagent policy.
- **Root Cause**: SubagentTracker only removes IDs on /subagent-stop. No TTL, no connection monitoring, no cleanup on server restart. In practice, server restarts clear the actor state (it's in-memory), but long-running servers accumulate stale IDs.
- **Status**: OPEN
- **Fix**: Add TTL-based expiry to tracked sessions, or clear on server restart (already happens implicitly since it's in-memory). For long-running servers, add a periodic sweep that removes IDs older than e.g. 24 hours.
- **Discovered**: 2026-04-23

### BUG-022: parseHTTP trims body whitespace
- **Description**: parseHTTP extracts the HTTP body as a String and calls trimmingCharacters(in: .whitespacesAndNewlines) before re-encoding to Data. This could silently strip meaningful trailing whitespace from JSON values. Also, the entire buffer is converted via String(data:encoding:.utf8) which returns nil for non-UTF-8 content.
- **Root Cause**: HTTP body is round-tripped through String instead of being sliced directly from the raw Data buffer by byte offset. Claude Code sends JSON (always UTF-8) so the nil case is unlikely in practice.
- **Status**: OPEN
- **Fix**: Parse HTTP headers as String but extract body as raw Data by byte offset from the original buffer. Remove the trimmingCharacters call.
- **Discovered**: 2026-04-23

### BUG-023: MenuBarView width 340px but PolicyGridView needs 400px
- **Description**: MenuBarView sets .frame(width: 340) but the policy grid now has 6 columns (added in three-mode-toggle). Column headers and toggle cells clip or overlap at 340px. StatusItemController sets popover.contentSize to 400px but the inner view constrains to 340px.
- **Root Cause**: MenuBarView.swift frame width was not updated when PolicyGridView expanded from 4 to 6 columns. The popover container is 400px but the content view clips to 340px.
- **Status**: OPEN
- **Fix**: Change MenuBarView .frame(width: 340) to .frame(width: 400) to match the popover contentSize.
- **Discovered**: 2026-04-23

### BUG-024: AwayPolicyCell displays ask as deny without normalizing
- **Description**: If a user manually sets an away column to "ask" in config.json, the AwayPolicyCell shows the deny icon/color (pink X) but the underlying value is ask. Clicking toggles from ask to allow (since value != .allow), skipping deny. Confusing one-click transition from apparent-deny to allow.
- **Root Cause**: AwayPolicyCell treats ask identically to deny visually but the toggle logic (value == .allow ? .deny : .allow) treats ask as "not allow" → sets to allow on first click.
- **Status**: OPEN
- **Fix**: Normalize ask to deny on load for away columns (enforce invariant), or sanitize on toggle: always write .allow or .deny, never preserve .ask in away columns.
- **Discovered**: 2026-04-23

### BUG-025: Data race on HTTP buffer (CRITICAL)
- **Description**: handleConnection uses a mutable `buffer` variable captured by nested readMore() closure. The receive handler runs on `.global()` queue (concurrent). If NWConnection dispatches callbacks on different threads, the buffer can be mutated from multiple threads simultaneously.
- **Root Cause**: HTTPServer.swift:96 — buffer is a value type (Data) captured by reference through the enclosing function scope. All connection handling uses `.global()` queue instead of a per-connection serial queue.
- **Status**: OPEN
- **Fix**: Pin each connection's receive callbacks to a dedicated serial DispatchQueue instead of `.global()`. e.g. `let connQueue = DispatchQueue(label: "gate.conn.\(conn.hashValue)")` and use it for both `conn.start(queue:)` and all receive calls.
- **Discovered**: 2026-04-23

### BUG-026: Retain cycle in StatusItemController Binding closures
- **Description**: MenuBarView receives a Binding that captures `self` strongly in both get and set closures. Since MenuBarView is inside the popover's NSHostingController, which is owned by self, this creates a retain cycle: StatusItemController -> popover -> NSHostingController -> MenuBarView -> Binding -> StatusItemController.
- **Root Cause**: StatusItemController.swift:58-63 — `Binding(get: { self.config }, set: { self.config = $0 })` captures self strongly.
- **Status**: OPEN
- **Fix**: Use `[weak self]` in Binding closures with guard: `Binding(get: { [weak self] in self?.config ?? PolicyConfig.defaultConfig() }, set: { [weak self] in self?.config = $0 })`.
- **Discovered**: 2026-04-23

### BUG-027: Port-in-use kill targets wrong port
- **Description**: handleServerStartFailure runs `lsof -ti :9191 | xargs kill -9` with hardcoded port. If user configured a different port in config.json, the kill command targets the wrong port.
- **Root Cause**: AppDelegate.swift:87 — port 9191 hardcoded in the bash -c string instead of reading from config.server.port.
- **Status**: OPEN
- **Fix**: Use `config.server.port` in the lsof command string. Requires passing config to the failure handler or reading it fresh.
- **Discovered**: 2026-04-23

### BUG-028: Timer never invalidated on quit
- **Description**: The 200ms refresh timer in AppDelegate is created with Timer() and added to RunLoop but never stored as a property. It cannot be invalidated in applicationWillTerminate, so it continues firing after teardown begins.
- **Root Cause**: AppDelegate.swift:36 — timer is a local variable, not a stored property. applicationWillTerminate stops the server but doesn't invalidate the timer.
- **Status**: OPEN
- **Fix**: Store timer as a property (`private var refreshTimer: Timer?`). Invalidate in applicationWillTerminate.
- **Discovered**: 2026-04-23

### BUG-029: Tilde paths in workspace config never match
- **Description**: If a user puts `~/Code/project` in the workspaces config array, it never matches because file_path from Claude Code uses absolute paths (~/...) and String.hasPrefix doesn't expand tilde.
- **Root Cause**: PolicyConfig.swift:108 — isInsideWorkspace does raw string prefix comparison without expanding ~ to the home directory.
- **Status**: OPEN
- **Fix**: Call `(ws as NSString).expandingTildeInPath` before prefix comparison.
- **Discovered**: 2026-04-23

### BUG-030: Force-unwrap in PolicyGridView Binding can crash
- **Description**: PolicyGridView uses `config.policies[tool]!` in every Binding get/set closure. If a FileWatcher hot-reload removes a tool from the config between the `if != nil` check and the Binding access, the force-unwrap crashes.
- **Root Cause**: PolicyGridView.swift:35-54 — race between SwiftUI Binding evaluation and config mutation from FileWatcher.
- **Status**: OPEN
- **Fix**: Use optional chaining in set closures: `config.policies[tool]?.parent = $0`. In get closures, provide a default: `config.policies[tool]?.parent ?? .ask`.
- **Discovered**: 2026-04-23

### BUG-031: Corrupt settings.json silently overwritten
- **Description**: Installer.loadSettings() returns empty dict if settings.json exists but is corrupt JSON. modifySettings() then writes this empty dict + claude-gate hooks back, destroying all other user settings (permissions, env, hooks from other tools).
- **Root Cause**: Installer.swift:150 — loadSettings returns `[:]` on parse failure instead of propagating the error or refusing to modify.
- **Status**: OPEN
- **Fix**: If JSON parse fails, throw an error and refuse to modify. Show the user: "settings.json is corrupt, please fix it manually before running --install."
- **Discovered**: 2026-04-23

### BUG-032: Keyboard shortcuts fire on all pending request rows
- **Description**: Ctrl+Shift+Y (allow) and Ctrl+Shift+N (deny) keyboard shortcuts are applied to every RequestRowView. When multiple requests are pending, pressing the shortcut approves/denies ALL requests simultaneously.
- **Root Cause**: RequestRowView.swift:48,58 — .keyboardShortcut applied inside ForEach, so every row gets the same shortcut. SwiftUI fires all matching buttons.
- **Status**: OPEN
- **Fix**: Only apply keyboard shortcuts to the first (topmost) row. Pass an `isFirst: Bool` parameter to RequestRowView and conditionally add the shortcut.
- **Discovered**: 2026-04-23

### BUG-033: Continuation dangling if listener cancelled before ready
- **Description**: In HTTPServer.start(), if NWListener enters .cancelled state before reaching .ready, the CheckedContinuation is never resumed. The async caller hangs forever.
- **Root Cause**: HTTPServer.swift:45-54 — the stateUpdateHandler only handles .ready and .failed, with `default: break` for all other states including .cancelled.
- **Status**: OPEN
- **Fix**: Add `.cancelled` case to the startup handler that resumes with an error.
- **Discovered**: 2026-04-23
