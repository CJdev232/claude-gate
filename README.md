# claude-gate

A macOS menu bar app that intercepts Claude Code's PermissionRequest hook and presents a native popover for approve/deny decisions. Supports three operational modes — Present, Remote, and Away — with workspace-aware auto-approve policies.

## Why

Claude Code asks for tool permissions in the terminal. Every decision requires a context switch back to the terminal window. When you step away, Claude stalls waiting for a response that never comes. claude-gate moves permission decisions to the menu bar, keeps Claude running when you're away, and lets you approve from your phone in Remote mode.

## Features

- Menu bar popover with approve/deny buttons and keyboard shortcuts
- Three modes: **Present** (30s timeout), **Remote** (5min, phone-friendly), **Away** (instant auto-decide)
- Workspace auto-detection from session `cwd` — different policies inside vs. outside the project
- Per-tool policy grid: configure parent/subagent behavior, timeout, and away-mode decisions
- Config hot-reload — edit `~/.claude-gate/config.json` and changes apply immediately
- `--mode` and `--restart` CLI flags for scripting and process management
- Coexists with Claude Code Remote Control and Happy

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Claude Code >= 2.1.98 (PermissionRequest hook support)

## Install

Build from source:

```sh
git clone <repo>
cd claude-gate
sudo make install       # release build, copy to /usr/local/bin, codesign
claude-gate --install   # register PermissionRequest hook in Claude Code
claude-gate &           # start the menu bar app
```

> Must run from a normal terminal, not from within a Claude Code session.

## Usage

| Action | How |
|--------|-----|
| Toggle popover | Left-click the menu bar icon |
| Switch mode | Right-click the menu bar icon |
| Set mode via CLI | `claude-gate --mode away` / `present` / `remote` |
| Restart process | `claude-gate --restart` |
| Edit policy | `~/.claude-gate/config.json` (hot-reloaded) |

When a permission request arrives, the popover opens automatically. Press **A** to approve or **D** to deny. If the timeout expires before you decide, the request is denied automatically.

## Three-Mode System

| Mode | Icon | Timeout | Behavior |
|------|------|---------|----------|
| Present | lock.shield | 30s | Popover opens for interactive approval. Normal desk use. |
| Remote | lock.shield (orange R) | 5 min | Extended timeout for approving from a phone via Remote Control. |
| Away | lock.shield (teal A) | instant | Auto-decides using per-tool away policies. No popover shown. |

Mode resets to Present on restart.

### Away mode workspace detection

In Away mode, each request is classified as inside or outside the current workspace:

- Tool `file_path` starts with session `cwd` → **inside** → uses `awayWorkspace` policy
- Otherwise → **outside** → uses `awayOutside` policy (defaults to deny)
- `Bash` commands are always treated as outside (target path not detectable)
- `Task` and `AskUserQuestion` are always treated as inside

## Config

Located at `~/.claude-gate/config.json`. Changes are detected and applied without restarting.

Minimal example:

```json
{
  "server": { "port": 9191 },
  "tools": {
    "Read": { "parent": "allow", "subagent": "allow", "timeout": "allow", "awayWorkspace": "allow", "awayOutside": "deny" },
    "Write": { "parent": "ask",   "subagent": "ask",   "timeout": "deny",  "awayWorkspace": "ask",   "awayOutside": "deny" }
  }
}
```

Policy values: `allow`, `deny`, `ask`.

## Version

Current release: **0.3.0.0**

See [CHANGELOG.md](CHANGELOG.md) for full version history.

## License

MIT
