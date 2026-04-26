# claude-gate

A macOS menu bar app that intercepts Claude Code's PermissionRequest hook and presents a native popover for approve/deny decisions. Supports three operational modes — Present, Remote, and Away — with workspace-aware auto-approve policies.

**[Try the interactive demo](https://neo.github.io/claude-gate/demo.html)** — no install needed, runs in your browser.

## Why

Claude Code asks for tool permissions in the terminal. Every decision requires a context switch. When you step away, Claude stalls waiting for a response that never comes.

claude-gate moves permission decisions to the menu bar. Approve or deny with a click. Switch to Away mode and Claude keeps working on safe operations inside your project — you review the results when you're back.

## Features

- **Menu bar popover** with approve/deny buttons and keyboard shortcuts
- **Three modes:** Present (30s), Remote (5min, phone-friendly), Away (instant auto-decide)
- **Workspace auto-detection** from session `cwd` — different policies inside vs. outside the project
- **Per-tool policy grid** — configure parent/subagent behavior, timeout, and away-mode decisions per tool
- **Config hot-reload** — edit `~/.claude-gate/config.json`, changes apply immediately
- **CLI control** — `--mode away`, `--restart`, `--install` for scripting
- **Coexists** with Claude Code Remote Control and Happy

## Demo

The interactive demo simulates a Claude Code session with claude-gate running. You can:
- Approve/deny permission requests in the simulated popover
- Switch between Present/Remote/Away modes
- Watch workspace detection in action (inside vs. outside project boundary)
- See the live decision log and policy grid

Open `demo.html` locally, or visit the [live demo](https://neo.github.io/claude-gate/demo.html).

## Install

Build from source (macOS 14+, Swift 5.9+, Claude Code >= 2.1.98):

```sh
git clone https://github.com/neo/claude-gate.git
cd claude-gate
sudo make install       # build, copy to /usr/local/bin, codesign
claude-gate --install   # register PermissionRequest hook in Claude Code
claude-gate &           # start the menu bar app
```

> **Note:** Must run `claude-gate &` from a normal terminal, not from within a Claude Code session.

## Usage

| Action | How |
|--------|-----|
| Toggle popover | Left-click the menu bar icon |
| Switch mode | Right-click the menu bar icon |
| Set mode via CLI | `claude-gate --mode away` / `present` / `remote` |
| Restart after rebuild | `sudo make restart` |
| Edit policies | `~/.claude-gate/config.json` (hot-reloaded) |

## Three-Mode System

| Mode | Icon | Timeout | Behavior |
|------|------|---------|----------|
| **Present** | lock.shield | 30s | Popover opens for interactive approval. Normal desk use. |
| **Remote** | lock.shield + orange **R** | 5 min | Extended timeout for approving from phone. |
| **Away** | lock.shield + teal **A** | instant | Auto-decides using workspace-aware policies. No popover. |

Mode resets to Present on restart.

### Away mode workspace detection

In Away mode, each request is classified by workspace boundary:

- `file_path` inside session `cwd` → **workspace** → uses `awayWorkspace` policy (default: allow for Write/Edit)
- `file_path` outside `cwd` → **outside** → uses `awayOutside` policy (default: deny)
- `Bash` → always treated as outside (shell commands can target any path)
- `Task` / `AskUserQuestion` → always treated as inside (session-internal)

## Config

Located at `~/.claude-gate/config.json`. Changes are detected and applied without restarting.

```json
{
  "server": {
    "port": 9191,
    "timeout": 30,
    "remote_timeout": 300
  },
  "policies": {
    "Read":  { "parent": "allow", "subagent": "allow", "timeout": "allow", "away_workspace": "allow", "away_outside": "allow" },
    "Write": { "parent": "ask",   "subagent": "ask",   "timeout": "deny",  "away_workspace": "allow", "away_outside": "deny" },
    "Bash":  { "parent": "ask",   "subagent": "deny",  "timeout": "deny",  "away_workspace": "deny",  "away_outside": "deny" }
  }
}
```

Policy values: `allow` (auto-approve), `ask` (show popover), `deny` (auto-reject).

## Architecture

```
Claude Code → PermissionRequest hook (HTTP POST)
  → HTTPServer (NWListener on port 9191)
    → PolicyConfig lookup + GateModeState check
    → Present/Remote: popover via StatusItemController
    → Away: auto-decide by workspace boundary
  → Response: { "hookSpecificOutput": { "decision": { "behavior": "allow" } } }
```

Key files: `HTTPServer.swift` (server + decision logic), `PolicyConfig.swift` (config + FileWatcher), `StatusItemController.swift` (UI + mode menu), `GateMode.swift` (mode state), `AppDelegate.swift` (wiring).

## Version

**0.3.0** — See [CHANGELOG.md](CHANGELOG.md) for full history.

## License

MIT
