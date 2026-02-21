#!/bin/bash

# Test suite for spawn-agent.sh
# Unit tests run anywhere. Integration tests require Zellij to be installed.

PASS=0
FAIL=0
SCRIPT="$(cd "$(dirname "$0")" && pwd)/spawn-agent.sh"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"

pass() { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1"; ((FAIL++)); }

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (expected: '$expected', got: '$actual')"
  fi
}

contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc (expected to contain: '$needle')"
  fi
}

excludes() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    fail "$desc (must not contain: '$needle')"
  else
    pass "$desc"
  fi
}

# ── Session name generation ────────────────────────────────────────────────────
echo "Session name generation:"

check "simple branch" \
  "mybranch" \
  "$(bash -c 'BRANCH_NAME=mybranch; echo "${BRANCH_NAME//\//-}"')"

check "feature/ prefix becomes dash" \
  "feature-fiddlesticks" \
  "$(bash -c 'BRANCH_NAME=feature/fiddlesticks; echo "${BRANCH_NAME//\//-}"')"

check "nested slashes all replaced" \
  "a-b-c" \
  "$(bash -c 'BRANCH_NAME=a/b/c; echo "${BRANCH_NAME//\//-}"')"

# ── Layout file generation (via the script with mock zellij) ──────────────────
echo "Layout file generation:"

MOCK_BIN_LAYOUT=$(mktemp -d)
cat > "$MOCK_BIN_LAYOUT/zellij" <<'MOCK'
#!/bin/bash
echo "zellij $*"
for arg in "$@"; do
  if [ -f "$arg" ] && [[ "$arg" == *.kdl ]]; then cat "$arg"; fi
done
MOCK
cat > "$MOCK_BIN_LAYOUT/lazygit" <<'MOCK'
#!/bin/bash
MOCK
chmod +x "$MOCK_BIN_LAYOUT/zellij" "$MOCK_BIN_LAYOUT/lazygit"

# Run the script inside-Zellij mode so it calls new-tab and emits the layout
out=$(ZELLIJ=1 ZELLIJ_SESSION_NAME=fake PATH="$MOCK_BIN_LAYOUT:$PATH" \
  "$SCRIPT" test-layout-branch claude 2>&1)
# Cleanup worktree/branch created by the script
git -C "$REPO_ROOT" worktree remove --force \
  "$HOME/.spawn-agent/$REPO_NAME/test-layout-branch" 2>/dev/null || true
git -C "$REPO_ROOT" branch -D test-layout-branch 2>/dev/null || true

contains "layout contains agent command"  'command="claude"'       "$out"
contains "layout contains lazygit"        'command="lazygit"'      "$out"
contains "layout contains tab-bar"        'zellij:tab-bar'          "$out"
contains "layout contains status-bar"     'zellij:status-bar'       "$out"
excludes "inside zellij layout: no tab{} wrapper" 'tab name='      "$out"

rm -rf "$MOCK_BIN_LAYOUT"

# ── Argument validation ────────────────────────────────────────────────────────
echo "Argument validation:"

out=$("$SCRIPT" 2>&1); code=$?
check "no args exits non-zero" "1" "$code"
contains "no args prints usage" "Usage:" "$out"

out=$("$SCRIPT" remove 2>&1); code=$?
check "remove without branch exits non-zero" "1" "$code"
contains "remove without branch prints usage" "Usage:" "$out"

# ── Dependency / environment checks ───────────────────────────────────────────
echo "Dependency checks:"

out=$(PATH="" "$SCRIPT" some-branch 2>&1); code=$?
check "missing zellij exits non-zero" "1" "$code"
contains "missing zellij prints error" "zellij is required" "$out"

# Mock zellij but not lazygit
MOCK_BIN_NOLG=$(mktemp -d)
cat > "$MOCK_BIN_NOLG/zellij" <<'MOCK'
#!/bin/bash
echo "zellij $*"
MOCK
chmod +x "$MOCK_BIN_NOLG/zellij"
out=$(PATH="$MOCK_BIN_NOLG" "$SCRIPT" some-branch 2>&1); code=$?
check "missing lazygit exits non-zero" "1" "$code"
contains "missing lazygit prints error" "lazygit is required" "$out"
rm -rf "$MOCK_BIN_NOLG"

NONGIT=$(mktemp -d)
out=$(cd "$NONGIT" && "$SCRIPT" some-branch 2>&1); code=$?
check "non-git dir exits non-zero" "1" "$code"
contains "non-git dir prints error" "not inside a git repository" "$out"
rm -rf "$NONGIT"

# ── Launch mode selection ─────────────────────────────────────────────────────
echo "Launch mode:"

# Mock zellij + lazygit; cats any .kdl file so we can inspect the layout
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/zellij" <<'MOCK'
#!/bin/bash
echo "zellij $*"
for arg in "$@"; do
  if [ -f "$arg" ] && [[ "$arg" == *.kdl ]]; then cat "$arg"; fi
done
MOCK
cat > "$MOCK_BIN/lazygit" <<'MOCK'
#!/bin/bash
MOCK
chmod +x "$MOCK_BIN/zellij" "$MOCK_BIN/lazygit"

# Shared cleanup for worktrees created during launch-mode tests
cleanup_test_branch() {
  git -C "$REPO_ROOT" worktree remove --force \
    "$HOME/.spawn-agent/$REPO_NAME/some-branch" 2>/dev/null || true
  git -C "$REPO_ROOT" branch -D some-branch 2>/dev/null || true
}

# Inside Zellij: new-tab, no tab wrapper in layout
out=$(ZELLIJ=1 ZELLIJ_SESSION_NAME=fake PATH="$MOCK_BIN:$PATH" "$SCRIPT" some-branch 2>&1)
cleanup_test_branch
contains "inside zellij: prints tab message"        "Opening tab"       "$out"
contains "inside zellij: calls action new-tab"      "action new-tab"    "$out"
excludes "inside zellij: layout has no tab wrapper" 'tab name='         "$out"

# Outside Zellij, no existing repo session: create session named after repo
out=$(ZELLIJ="" ZELLIJ_SESSION_NAME="" PATH="$MOCK_BIN:$PATH" "$SCRIPT" some-branch 2>&1)
cleanup_test_branch
contains "outside zellij (new): prints session message"          "Creating Zellij session"            "$out"
contains "outside zellij (new): session named after repo"        "$REPO_NAME"                         "$out"
contains "outside zellij (new): calls --new-session-with-layout" "zellij --new-session-with-layout"   "$out"
contains "outside zellij (new): layout has tab wrapper"          'tab name="some-branch"'             "$out"

# Outside Zellij, repo session already exists: add tab and attach
MOCK_BIN2=$(mktemp -d)
cat > "$MOCK_BIN2/zellij" <<MOCK2
#!/bin/bash
if [ "\$1" = "list-sessions" ]; then echo "$REPO_NAME"; fi
echo "zellij \$*"
for arg in "\$@"; do
  if [ -f "\$arg" ] && [[ "\$arg" == *.kdl ]]; then cat "\$arg"; fi
done
MOCK2
cat > "$MOCK_BIN2/lazygit" <<'MOCK'
#!/bin/bash
MOCK
chmod +x "$MOCK_BIN2/zellij" "$MOCK_BIN2/lazygit"

out=$(ZELLIJ="" ZELLIJ_SESSION_NAME="" PATH="$MOCK_BIN2:$PATH" "$SCRIPT" some-branch 2>&1)
cleanup_test_branch
contains "outside zellij (existing): attaches to repo session" "Attaching to session '$REPO_NAME'" "$out"
contains "outside zellij (existing): calls action new-tab"     "action new-tab"                   "$out"
contains "outside zellij (existing): calls attach"             "zellij attach $REPO_NAME"         "$out"

rm -rf "$MOCK_BIN" "$MOCK_BIN2"

# ── Integration: layout loading via background session ────────────────────────
echo "Integration (requires Zellij):"

if ! command -v zellij &>/dev/null; then
  echo "  ⚠️  Zellij not found, skipping integration tests"
else
  TEST_SESSION="spawn-agent-test-$$"
  zellij attach --create-background "$TEST_SESSION" 2>/dev/null

  LAYOUT=$(mktemp "${TMPDIR:-/tmp}/spawn-agent-XXXXXX.kdl")
  cat > "$LAYOUT" <<EOF2
layout {
    pane size=1 borderless=true {
        plugin location="zellij:tab-bar"
    }
    pane split_direction="vertical" {
        pane command="bash" cwd="/tmp" size="70%"
        pane command="bash" cwd="/tmp" size="30%"
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
EOF2

  ZELLIJ_SESSION_NAME="$TEST_SESSION" zellij action new-tab \
    --layout "$LAYOUT" --name "integration-test" 2>/dev/null
  code=$?
  check "new-tab with layout exits 0" "0" "$code"

  DUMP=$(ZELLIJ_SESSION_NAME="$TEST_SESSION" zellij action dump-layout 2>/dev/null)
  contains "tab appears in session layout" 'tab name="integration-test"' "$DUMP"
  contains "tab has tab-bar"    'plugin location="zellij:tab-bar"'    "$DUMP"
  contains "tab has status-bar" 'plugin location="zellij:status-bar"' "$DUMP"

  rm -f "$LAYOUT"
  zellij kill-session "$TEST_SESSION" 2>/dev/null
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
