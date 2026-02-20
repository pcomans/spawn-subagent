# spawn-subagent

A shell script for spawning AI coding agents (or any command) in isolated git worktrees, each in their own tmux window.

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

## Per-repo setup

Create `.spawn-agent/setup.sh` in your repo to run custom setup when a worktree is created (copy `.env`, install deps, etc.). It receives two arguments:

```bash
#!/bin/bash
REPO_ROOT=$1
WORKTREE_PATH=$2

cp "$REPO_ROOT/.env" "$WORKTREE_PATH/"
```

## Requirements

- git
- tmux (optional — without it, the script drops into the worktree directory)
