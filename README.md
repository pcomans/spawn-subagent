# spawn-subagent

A shell script for spawning AI coding agents in isolated git worktrees, each in their own Zellij session.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/pcomans/spawn-subagent/main/install.sh | bash
```

Installs `spawn-agent` to `/usr/local/bin` (or `~/.local/bin` if that isn't writable).

## Usage

```bash
spawn-agent <branch-name>
```

- `branch-name` — created from the default branch if it doesn't exist, reattached if it does

Worktrees are stored under `~/.spawn-agent/<repo-name>/<branch-name>`.

Each session opens with a shell on the left (70%) and lazygit on the right (30%).

## Removing a worktree

```bash
spawn-agent remove <branch-name>
```

Runs `.spawn-agent/teardown.sh` (if present), removes the worktree, and kills the Zellij session. Fails with a clear error if the worktree has uncommitted changes. The local git branch is not deleted.

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

## Custom layout

Create `.spawn-agent/layout.kdl` to override the default Zellij layout. Use `{{cwd}}` as a placeholder for the worktree path:

```kdl
layout {
    pane split_direction="vertical" {
        pane cwd="{{cwd}}" size="70%"
        pane command="lazygit" cwd="{{cwd}}" size="30%"
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
```

## Navigating Zellij sessions

Each worktree gets its own Zellij session named after the branch.

| Action | Command |
|---|---|
| Open session manager | `Ctrl-o w` |
| Detach from session | `Ctrl-o d` |
| New pane | `Ctrl-p n` |
| Split pane right | `Ctrl-p d` |
| Split pane down | `Ctrl-p D` |
| Switch between panes | `Ctrl-p` + arrow keys |
| List sessions | `zellij list-sessions` |
| Attach to session | `zellij attach <branch-name>` |

## Zellij setup

### Copy/paste (macOS)

Zellij requires an explicit copy command. Add this to your `~/.config/zellij/config.kdl`:

```kdl
copy_command "pbcopy"
```

## Requirements

- git
- [Zellij](https://zellij.dev)
- [lazygit](https://github.com/jesseduffield/lazygit)
