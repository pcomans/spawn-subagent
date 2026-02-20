# Agent Instructions

## Testing

Run the test suite before and after changes:

```bash
bash /tmp/spawn-agent-zellij/test.sh
```

The suite has two levels:

### Unit tests (always run)
- Session name sanitization (`/` → `-`)
- Layout file content (tab-bar, status-bar, agent command, cwd, lazygit)
- Argument validation (no args, remove without branch)
- Dependency checks (missing zellij, non-git directory)

### Integration tests (require Zellij installed)
Uses `zellij attach --create-background SESSION` to create a headless session,
then runs `ZELLIJ_SESSION_NAME=SESSION zellij action ...` to test against it,
then verifies state with `zellij action dump-layout`.

This lets you test layout loading and tab creation without a live terminal.

```bash
# The integration test does this automatically, but you can also run manually:
SESSION=spawn-agent-test-manual
zellij attach --create-background "$SESSION"
ZELLIJ_SESSION_NAME="$SESSION" zellij action new-tab --layout my-layout.kdl --name test
ZELLIJ_SESSION_NAME="$SESSION" zellij action dump-layout   # inspect the result
zellij kill-session "$SESSION"
```

### What still requires manual testing
- Visual appearance of the tab (pane sizes, chrome rendering)
- Agent command actually launching (claude, lazygit)
- End-to-end: running spawn-agent.sh from inside a live Zellij session

For end-to-end testing, run from inside an existing Zellij session:
```bash
./spawn-agent.sh feature/test-branch claude
# Expected: new tab opens with left pane (claude) + right pane (lazygit)
# Expected: tab-bar at top, status-bar at bottom
# Expected: tab named "feature-test-branch"

./spawn-agent.sh remove feature/test-branch
# Expected: worktree removed, branch preserved, tab note printed
```

## Session name format

Branch names are sanitized by replacing `/` with `-`:
- `feature/my-branch` → tab named `feature-my-branch`
- `main` → tab named `main`

## Layout format

The default layout (`.spawn-agent/layout.kdl` override supported) must:
- Include `plugin location="zellij:tab-bar"` as first pane
- Include `plugin location="zellij:status-bar"` as last pane
- NOT wrap content in a `tab { }` block (that's for session layouts, not `new-tab`)
- Use `{{cwd}}` and `{{agent_cmd}}` as template variables when providing a custom layout

## Key Zellij behaviors discovered

- `zellij --session NAME --layout FILE` inside a session: adds layout as new tab to NAME (not create)
- `zellij --new-session-with-layout FILE`: creates nested session (wrong for our use case)
- `zellij action new-tab --layout FILE --name NAME`: correct way to open a tab in current session
- `ZELLIJ_SESSION_NAME=NAME zellij action ...`: targets a specific session (works from outside it)
- `zellij action dump-layout`: inspects current session layout state (useful for testing)
- `new-tab --layout` does NOT inherit `default_tab_template`; tab-bar/status-bar must be explicit
