#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ -z "$1" ]; then
  echo "Usage: spawn-agent <branch-name> [agent-command]"
  echo "       spawn-agent remove <branch-name>"
  echo "       spawn-agent init"
  exit 1
fi

# Require tmux
if ! command -v tmux &>/dev/null; then
  echo "Error: tmux is required but not installed."
  exit 1
fi

# Require git repo
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "Error: not inside a git repository."
  exit 1
fi

REPO_NAME=$(basename "$REPO_ROOT")

# Handle init subcommand
if [ "$1" = "init" ]; then
  mkdir -p "$REPO_ROOT/.spawn-agent"
  for script in setup teardown; do
    SCRIPT_PATH="$REPO_ROOT/.spawn-agent/$script.sh"
    if [ -f "$SCRIPT_PATH" ]; then
      echo "⚠️  .spawn-agent/$script.sh already exists, skipping"
    else
      cat > "$SCRIPT_PATH" <<'EOF'
#!/bin/bash
REPO_ROOT=$1
WORKTREE_PATH=$2
EOF
      chmod +x "$SCRIPT_PATH"
      echo "✅ Created .spawn-agent/$script.sh"
    fi
  done
  exit 0
fi

# Handle remove subcommand
if [ "$1" = "remove" ]; then
  if [ -z "$2" ]; then
    echo "Usage: spawn-agent remove <branch-name>"
    exit 1
  fi
  BRANCH_NAME=$2
  WORKTREE_PATH="$HOME/.spawn-agent/$REPO_NAME/$BRANCH_NAME"
  if [ -f "$REPO_ROOT/.spawn-agent/teardown.sh" ]; then
    echo "⚙️  Running .spawn-agent/teardown.sh..."
    bash "$REPO_ROOT/.spawn-agent/teardown.sh" "$REPO_ROOT" "$WORKTREE_PATH"
  fi
  if ! git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
    echo "Error: could not remove worktree. It may have uncommitted changes."
    echo "Commit or stash your changes, then try again."
    exit 1
  fi
  tmux kill-session -t "$BRANCH_NAME" 2>/dev/null || true
  echo "✅ Removed worktree and session for '$BRANCH_NAME'"
  echo "ℹ️  Local branch '$BRANCH_NAME' was not deleted."
  exit 0
fi

BRANCH_NAME=$1
# Default to opening a standard shell if no agent is specified
AGENT_CMD=${2:-"$SHELL"}

# Detect default base branch
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || BASE_BRANCH="main"

# Define the new centralized worktree path
BASE_WORKTREE_DIR="$HOME/.spawn-agent/$REPO_NAME"
WORKTREE_PATH="$BASE_WORKTREE_DIR/$BRANCH_NAME"

# Check if the worktree directory already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "⚠️  Worktree already exists, reattaching..."
else
  mkdir -p "$BASE_WORKTREE_DIR"
  echo "🚀 Creating workspace for '$BRANCH_NAME' at $WORKTREE_PATH..."

  # Handle existing vs new branches
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "🌿 Branch '$BRANCH_NAME' exists. Attaching worktree..."
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  else
    echo "🌱 Creating new branch '$BRANCH_NAME' from '$BASE_BRANCH'..."
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
  fi

  # Run per-repo setup if present
  if [ -f "$REPO_ROOT/.spawn-agent/setup.sh" ]; then
    echo "⚙️  Running .spawn-agent/setup.sh..."
    bash "$REPO_ROOT/.spawn-agent/setup.sh" "$REPO_ROOT" "$WORKTREE_PATH"
    echo "✅ Setup complete"
  fi
fi

# Create or reattach tmux session
if tmux has-session -t "$BRANCH_NAME" 2>/dev/null; then
  echo "🪟 Session '$BRANCH_NAME' already exists, switching..."
else
  echo "🪟 Creating tmux session '$BRANCH_NAME'..."
  tmux new-session -d -s "$BRANCH_NAME" -c "$WORKTREE_PATH" "$AGENT_CMD"
fi

if [ -n "$TMUX" ]; then
  tmux switch-client -t "$BRANCH_NAME"
else
  tmux attach-session -t "$BRANCH_NAME"
fi
