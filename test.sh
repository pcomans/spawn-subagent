#!/bin/bash

# Test suite for spawn-agent.sh
# Unit tests run anywhere. Integration tests require Zellij to be installed.

PASS=0
FAIL=0
SCRIPT="$(dirname "$0")/spawn-agent.sh"

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

# ── Layout file generation ─────────────────────────────────────────────────────
echo "Layout file generation:"

TMPDIR_TEST=$(mktemp -d)
LAYOUT_OUT="$TMPDIR_TEST/layout.kdl"
AGENT_CMD="claude"
WORKTREE_PATH="/tmp/test-worktree"

cat > "$LAYOUT_OUT" <<EOF
layout {
    pane size=1 borderless=true {
        plugin location="zellij:tab-bar"
    }
    pane split_direction="vertical" {
        pane command="$AGENT_CMD" cwd="$WORKTREE_PATH" size="70%"
        pane command="lazygit" cwd="$WORKTREE_PATH" size="30%"
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
EOF

LAYOUT_CONTENT="$(cat "$LAYOUT_OUT")"
contains "layout contains agent command"  'command="claude"'       "$LAYOUT_CONTENT"
contains "layout contains worktree cwd"   'cwd="/tmp/test-worktree"' "$LAYOUT_CONTENT"
contains "layout contains lazygit"        'command="lazygit"'      "$LAYOUT_CONTENT"
contains "layout contains tab-bar"        'zellij:tab-bar'          "$LAYOUT_CONTENT"
contains "layout contains status-bar"     'zellij:status-bar'       "$LAYOUT_CONTENT"
excludes "layout has no tab{} wrapper"    'tab name='               "$LAYOUT_CONTENT"
rm -rf "$TMPDIR_TEST"

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

NONGIT=$(mktemp -d)
out=$(cd "$NONGIT" && "$SCRIPT" some-branch 2>&1); code=$?
check "non-git dir exits non-zero" "1" "$code"
contains "non-git dir prints error" "not inside a git repository" "$out"
rm -rf "$NONGIT"

# ── Launch mode selection ─────────────────────────────────────────────────────
echo "Launch mode:"

# Use a mock zellij that records args instead of running
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/zellij" <<'MOCK'
#!/bin/bash
echo "zellij $*"
MOCK
chmod +x "$MOCK_BIN/zellij"

# Inside Zellij: should call "zellij action new-tab"
out=$(ZELLIJ=1 ZELLIJ_SESSION_NAME=fake PATH="$MOCK_BIN:$PATH" "$SCRIPT" some-branch 2>&1)
contains "inside zellij: prints tab message" "Opening tab" "$out"
contains "inside zellij: calls action new-tab" "action new-tab" "$out"

# Outside Zellij: should call "zellij --session"
out=$(ZELLIJ="" ZELLIJ_SESSION_NAME="" PATH="$MOCK_BIN:$PATH" "$SCRIPT" some-branch 2>&1)
contains "outside zellij: prints session message" "Creating Zellij session" "$out"
contains "outside zellij: calls --new-session-with-layout" "zellij --new-session-with-layout" "$out"

rm -rf "$MOCK_BIN"

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
