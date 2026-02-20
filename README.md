# spawn-subagent

A shell script for spawning AI coding agents (or any command) in isolated git worktrees, each in their own tmux session.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/pcomans/spawn-subagent/main/install.sh | bash
```

Installs `spawn-agent` to `/usr/local/bin` (or `~/.local/bin` if that isn't writable).

## Usage

```bash
spawn-agent <branch-name> [agent-command]
```

- `branch-name` — created from the default branch if it doesn't exist, reattached if it does
- `agent-command` — defaults to `$SHELL`; pass `claude`, `aider`, etc.

Worktrees are stored under `~/.spawn-agent/<repo-name>/<branch-name>`.

## Removing a worktree

```bash
spawn-agent remove <branch-name>
```

Runs `.spawn-agent/teardown.sh` (if present), removes the worktree, and kills the tmux session. Fails with a clear error if the worktree has uncommitted changes. The local git branch is not deleted.

## Init

```bash
spawn-agent init
```

Creates `.spawn-agent/setup.sh` and `.spawn-agent/teardown.sh` in the current repo if they don't already exist.

## Per-repo hooks

Create `.spawn-agent/setup.sh` to run custom setup when a worktree is created (copy `.env`, install deps, etc.):

```bash
#!/bin/bash
REPO_ROOT=$1
WORKTREE_PATH=$2

cp "$REPO_ROOT/.env" "$WORKTREE_PATH/"
```

Create `.spawn-agent/teardown.sh` to clean up when a worktree is removed (stop dev servers, remove copied files, etc.):

```bash
#!/bin/bash
REPO_ROOT=$1
WORKTREE_PATH=$2

rm -f "$WORKTREE_PATH/.env"
```

## Navigating tmux sessions

Each worktree gets its own tmux session named after the branch.

| Action | Command |
|---|---|
| Switch to another session | `Ctrl-b (` / `)` (prev/next) |
| Pick a session interactively | `Ctrl-b s` |
| List all sessions | `tmux list-sessions` |
| New window in current session | `Ctrl-b c` |
| Split pane horizontally | `Ctrl-b %` |
| Split pane vertically | `Ctrl-b "` |
| Switch between panes | `Ctrl-b` + arrow keys |
| Detach from session | `Ctrl-b d` |
| Reattach from outside tmux | `tmux attach -t <branch-name>` |

## Requirements

- git
- tmux
