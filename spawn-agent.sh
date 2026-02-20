#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ -z "$1" ]; then
  echo "Usage: ./spawn-agent.sh <branch-name> [agent-command]"
  echo "       ./spawn-agent.sh remove <branch-name>"
  exit 1
fi

# Get repository details
REPO_ROOT=$(git rev-parse --show-toplevel)
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
    echo "Usage: ./spawn-agent.sh remove <branch-name>"
    exit 1
  fi
  BRANCH_NAME=$2
  WORKTREE_PATH="$HOME/.spawn-agent/$REPO_NAME/$BRANCH_NAME"
  if [ -f "$REPO_ROOT/.spawn-agent/teardown.sh" ]; then
    echo "⚙️  Running .spawn-agent/teardown.sh..."
    bash "$REPO_ROOT/.spawn-agent/teardown.sh" "$REPO_ROOT" "$WORKTREE_PATH"
  fi
  git worktree remove "$WORKTREE_PATH"
  echo "✅ Removed worktree for '$BRANCH_NAME'"
  exit 0
fi

BRANCH_NAME=$1
# Default to opening a standard shell if no agent is specified
AGENT_CMD=${2:-"$SHELL"}

# Define the new centralized worktree path
BASE_WORKTREE_DIR="$HOME/.spawn-agent/$REPO_NAME"
WORKTREE_PATH="$BASE_WORKTREE_DIR/$BRANCH_NAME"

# Check if the worktree directory already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "⚠️  Worktree path $WORKTREE_PATH already exists!"
  echo "Skipping git setup and launching agent..."
else
  # Ensure the base storage directory exists
  mkdir -p "$BASE_WORKTREE_DIR"
  echo "🚀 Creating workspace for $BRANCH_NAME at $WORKTREE_PATH..."

  # 1. True Parallel Execution: Handle existing vs new branches
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "🌿 Branch '$BRANCH_NAME' exists. Attaching worktree..."
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  else
    echo "🌱 Creating new branch '$BRANCH_NAME'..."
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main
  fi

  # 2. Automated Environment Setup
  if [ -f "$REPO_ROOT/.spawn-agent/setup.sh" ]; then
    echo "⚙️  Running .spawn-agent/setup.sh..."
    bash "$REPO_ROOT/.spawn-agent/setup.sh" "$REPO_ROOT" "$WORKTREE_PATH"
    echo "✅ Setup complete"
  fi
fi

# 3. Tmux Session per Worktree
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