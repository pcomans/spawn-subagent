# spawn-subagent

A shell script for spawning AI coding agents (or any command) in isolated git worktrees, each in their own tmux session.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/pcomans/spawn-subagent/main/install.sh | sh
```

Installs `spawn-agent` to `/usr/local/bin` (or `~/.local/bin` if that isn't writable).

## Usage

```bash
./spawn-agent.sh <branch-name> [agent-command]
```

- `branch-name` — created if it doesn't exist, reused if it does
- `agent-command` — defaults to `$SHELL`; pass `claude`, `aider`, etc.

Worktrees are stored under `~/.spawn-agent/<repo-name>/<branch-name>`.

## Removing a worktree

```bash
./spawn-agent.sh remove <branch-name>
```

Runs `.spawn-agent/teardown.sh` (if present) before removing the worktree. The teardown script receives the same two arguments as setup (`$REPO_ROOT`, `$WORKTREE_PATH`).

## Init

```bash
./spawn-agent.sh init
```

Creates `.spawn-agent/setup.sh` and `.spawn-agent/teardown.sh` in the current repo if they don't already exist.

## Per-repo setup

Create `.spawn-agent/setup.sh` in your repo to run custom setup when a worktree is created (copy `.env`, install deps, etc.). It receives two arguments:

```bash
#!/bin/bash
REPO_ROOT=$1
WORKTREE_PATH=$2

cp "$REPO_ROOT/.env" "$WORKTREE_PATH/"
```

## Navigating tmux sessions

Each worktree gets its own tmux session named after the branch.

| Action | Command |
|---|---|
| Switch to another session | `Ctrl-b (` / `)` (prev/next) |
| Pick a session interactively | `Ctrl-b s` |
| New window in current session | `Ctrl-b c` |
| Split pane horizontally | `Ctrl-b %` |
| Split pane vertically | `Ctrl-b "` |
| Switch between panes | `Ctrl-b` + arrow keys |
| Detach from session | `Ctrl-b d` |
| Reattach from outside tmux | `tmux attach -t <branch-name>` |

## Requirements

- git
- tmux (optional — without it, the script drops into the worktree directory)
