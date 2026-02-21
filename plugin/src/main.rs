mod ui;

use std::collections::BTreeMap;
use std::path::PathBuf;
use zellij_tile::prelude::*;

// Command context keys used to route RunCommandResult
const CMD_GIT_TOPLEVEL: &str = "git_toplevel";
const CMD_LIST_WORKTREES: &str = "list_worktrees";
const CMD_GIT_BRANCHES: &str = "git_branches";
const CMD_SPAWN: &str = "spawn";
const CMD_REMOVE: &str = "remove";

#[derive(Debug, Clone, PartialEq)]
pub enum Mode {
    Loading,
    BrowseWorktrees,
    SelectBranch,
    InputBranch,
    Confirming,
}

impl Default for Mode {
    fn default() -> Self {
        Mode::Loading
    }
}

#[derive(Debug, Clone, Default)]
pub struct Worktree {
    pub path: String,
    pub branch: String,
}

#[derive(Default)]
struct State {
    mode: Mode,
    repo_root: String,
    repo_name: String,
    worktrees: Vec<Worktree>,
    branches: Vec<String>,
    filtered_branches: Vec<String>,
    selected_index: usize,
    input_buffer: String,
    agent_cmd: String,
    status_message: String,
    status_is_error: bool,
    spawn_agent_path: String,
}

register_plugin!(State);

/// Parse `git worktree list --porcelain` output, returning only worktrees under spawn_prefix.
pub fn parse_worktrees(output: &str, spawn_prefix: &str) -> Vec<Worktree> {
    let mut worktrees = Vec::new();
    let mut current_path = String::new();

    for line in output.lines() {
        if let Some(path) = line.strip_prefix("worktree ") {
            current_path = path.to_string();
        } else if let Some(branch_ref) = line.strip_prefix("branch ") {
            if current_path.starts_with(spawn_prefix) {
                let branch = branch_ref
                    .strip_prefix("refs/heads/")
                    .unwrap_or(branch_ref)
                    .to_string();
                worktrees.push(Worktree {
                    path: current_path.clone(),
                    branch,
                });
            }
        }
    }

    worktrees
}

/// Parse `git branch --format=%(refname:short)` output into a list of branch names.
pub fn parse_branches(output: &str) -> Vec<String> {
    output
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect()
}


impl State {
    fn ctx(cmd_type: &str) -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("cmd_type".to_string(), cmd_type.to_string());
        m
    }

    fn fire_git_toplevel(&self) {
        run_command(&["git", "rev-parse", "--show-toplevel"], Self::ctx(CMD_GIT_TOPLEVEL));
    }

    fn fire_list_worktrees(&self) {
        run_command_with_env_variables_and_cwd(
            &["git", "worktree", "list", "--porcelain"],
            BTreeMap::new(),
            PathBuf::from(&self.repo_root),
            Self::ctx(CMD_LIST_WORKTREES),
        );
    }

    fn fire_git_branches(&self) {
        run_command_with_env_variables_and_cwd(
            &["git", "branch", "--format=%(refname:short)"],
            BTreeMap::new(),
            PathBuf::from(&self.repo_root),
            Self::ctx(CMD_GIT_BRANCHES),
        );
    }

    fn fire_spawn(&self, branch: &str) {
        let mut env = BTreeMap::new();
        if let Ok(val) = std::env::var("ZELLIJ") {
            env.insert("ZELLIJ".to_string(), val);
        }
        if let Ok(val) = std::env::var("ZELLIJ_SESSION_NAME") {
            env.insert("ZELLIJ_SESSION_NAME".to_string(), val);
        }

        let mut ctx = Self::ctx(CMD_SPAWN);
        ctx.insert("branch".to_string(), branch.to_string());

        run_command_with_env_variables_and_cwd(
            &[&self.spawn_agent_path, branch, &self.agent_cmd],
            env,
            PathBuf::from(&self.repo_root),
            ctx,
        );
    }

    fn fire_remove(&self, branch: &str) {
        let mut env = BTreeMap::new();
        if let Ok(val) = std::env::var("ZELLIJ") {
            env.insert("ZELLIJ".to_string(), val);
        }

        let mut ctx = Self::ctx(CMD_REMOVE);
        ctx.insert("branch".to_string(), branch.to_string());

        run_command_with_env_variables_and_cwd(
            &[&self.spawn_agent_path, "remove", branch],
            env,
            PathBuf::from(&self.repo_root),
            ctx,
        );
    }

    fn handle_git_toplevel(&mut self, exit_code: Option<i32>, stdout: &[u8], stderr: &[u8]) {
        if exit_code != Some(0) {
            let err = String::from_utf8_lossy(stderr);
            self.status_message = format!("Not a git repo: {err}");
            self.status_is_error = true;
            return;
        }
        let root = String::from_utf8_lossy(stdout).trim().to_string();
        self.repo_name = root
            .rsplit('/')
            .next()
            .unwrap_or("unknown")
            .to_string();
        self.repo_root = root;
        self.mode = Mode::BrowseWorktrees;
        self.fire_list_worktrees();
        self.fire_git_branches();
    }

    fn handle_list_worktrees(&mut self, _exit_code: Option<i32>, stdout: &[u8]) {
        let output = String::from_utf8_lossy(stdout);
        let home = std::env::var("HOME").unwrap_or_default();
        let spawn_prefix = format!("{}/.spawn-agent/{}/", home, self.repo_name);

        self.worktrees = parse_worktrees(&output, &spawn_prefix);
        if self.selected_index >= self.worktrees.len() && !self.worktrees.is_empty() {
            self.selected_index = self.worktrees.len() - 1;
        }
    }

    fn handle_git_branches(&mut self, _exit_code: Option<i32>, stdout: &[u8]) {
        let output = String::from_utf8_lossy(stdout);
        self.branches = parse_branches(&output);
    }


    fn handle_spawn_result(&mut self, exit_code: Option<i32>, stderr: &[u8], context: &BTreeMap<String, String>) {
        let branch = context.get("branch").cloned().unwrap_or_default();
        if exit_code == Some(0) {
            self.status_message = format!("Spawned '{branch}'");
            self.status_is_error = false;
        } else {
            let err = String::from_utf8_lossy(stderr).trim().to_string();
            self.status_message = format!("Error: {err}");
            self.status_is_error = true;
        }
        self.fire_list_worktrees();
    }

    fn handle_remove_result(&mut self, exit_code: Option<i32>, stderr: &[u8], context: &BTreeMap<String, String>) {
        let branch = context.get("branch").cloned().unwrap_or_default();
        if exit_code == Some(0) {
            self.status_message = format!("Removed '{branch}'");
            self.status_is_error = false;
        } else {
            let err = String::from_utf8_lossy(stderr).trim().to_string();
            self.status_message = format!("Remove failed: {err}");
            self.status_is_error = true;
        }
        self.mode = Mode::BrowseWorktrees;
        self.fire_list_worktrees();
    }

    fn handle_key_browse(&mut self, key: &KeyWithModifier) {
        if key.has_no_modifiers() {
            match key.bare_key {
                BareKey::Char('j') | BareKey::Down => {
                    if !self.worktrees.is_empty() {
                        self.selected_index = (self.selected_index + 1) % self.worktrees.len();
                    }
                }
                BareKey::Char('k') | BareKey::Up => {
                    if !self.worktrees.is_empty() {
                        self.selected_index = if self.selected_index == 0 {
                            self.worktrees.len() - 1
                        } else {
                            self.selected_index - 1
                        };
                    }
                }
                BareKey::Enter => {
                    if let Some(wt) = self.worktrees.get(self.selected_index) {
                        let branch = wt.branch.clone();
                        self.status_message = format!("Spawning '{branch}'...");
                        self.status_is_error = false;
                        self.fire_spawn(&branch);
                    }
                }
                BareKey::Char('n') => {
                    self.filtered_branches = self.branches.clone();
                    self.mode = Mode::SelectBranch;
                    self.selected_index = 0;
                }
                BareKey::Char('i') => {
                    self.mode = Mode::InputBranch;
                    self.input_buffer.clear();
                }
                BareKey::Char('d') => {
                    if !self.worktrees.is_empty() {
                        self.mode = Mode::Confirming;
                    }
                }
                BareKey::Char('r') => {
                    self.fire_list_worktrees();
                    self.fire_git_branches();
                    self.status_message = "Refreshed".to_string();
                    self.status_is_error = false;
                }
                BareKey::Char('q') | BareKey::Esc => {
                    close_self();
                }
                _ => {}
            }
        }
    }

    fn handle_key_select_branch(&mut self, key: &KeyWithModifier) {
        if key.has_no_modifiers() {
            match key.bare_key {
                BareKey::Char('j') | BareKey::Down => {
                    if !self.filtered_branches.is_empty() {
                        self.selected_index = (self.selected_index + 1) % self.filtered_branches.len();
                    }
                }
                BareKey::Char('k') | BareKey::Up => {
                    if !self.filtered_branches.is_empty() {
                        self.selected_index = if self.selected_index == 0 {
                            self.filtered_branches.len() - 1
                        } else {
                            self.selected_index - 1
                        };
                    }
                }
                BareKey::Enter => {
                    if let Some(branch) = self.filtered_branches.get(self.selected_index).cloned() {
                        self.status_message = format!("Spawning '{branch}'...");
                        self.status_is_error = false;
                        self.mode = Mode::BrowseWorktrees;
                        self.fire_spawn(&branch);
                    }
                }
                BareKey::Esc => {
                    self.mode = Mode::BrowseWorktrees;
                    self.selected_index = 0;
                }
                _ => {}
            }
        }
    }

    fn handle_key_input_branch(&mut self, key: &KeyWithModifier) {
        let no_mod = key.has_no_modifiers();
        let shift_only = key.key_modifiers.len() == 1
            && key.key_modifiers.contains(&KeyModifier::Shift);

        match key.bare_key {
            BareKey::Enter if no_mod => {
                let branch = self.input_buffer.trim().to_string();
                if !branch.is_empty() {
                    self.status_message = format!("Spawning '{branch}'...");
                    self.status_is_error = false;
                    self.mode = Mode::BrowseWorktrees;
                    self.fire_spawn(&branch);
                }
            }
            BareKey::Esc if no_mod => {
                self.mode = Mode::BrowseWorktrees;
                self.selected_index = 0;
            }
            BareKey::Backspace if no_mod => {
                self.input_buffer.pop();
            }
            BareKey::Char(c) if no_mod || shift_only => {
                self.input_buffer.push(c);
            }
            _ => {}
        }
    }

    fn handle_key_confirming(&mut self, key: &KeyWithModifier) {
        if key.has_no_modifiers() {
            match key.bare_key {
                BareKey::Char('y') => {
                    if let Some(wt) = self.worktrees.get(self.selected_index) {
                        let branch = wt.branch.clone();
                        self.status_message = format!("Removing '{branch}'...");
                        self.status_is_error = false;
                        self.fire_remove(&branch);
                    }
                }
                BareKey::Char('n') | BareKey::Esc => {
                    self.mode = Mode::BrowseWorktrees;
                }
                _ => {}
            }
        }
    }
}

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        self.agent_cmd = configuration
            .get("agent_cmd")
            .cloned()
            .unwrap_or_else(|| "claude".to_string());

        self.spawn_agent_path = configuration
            .get("spawn_agent_path")
            .cloned()
            .unwrap_or_else(|| "spawn-agent".to_string());

        request_permission(&[
            PermissionType::RunCommands,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadApplicationState,
        ]);

        subscribe(&[
            EventType::Key,
            EventType::RunCommandResult,
            EventType::PermissionRequestResult,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                self.fire_git_toplevel();
                true
            }
            Event::PermissionRequestResult(PermissionStatus::Denied) => {
                self.status_message = "Permissions denied. Plugin cannot run commands.".to_string();
                self.status_is_error = true;
                true
            }
            Event::RunCommandResult(exit_code, stdout, stderr, context) => {
                match context.get("cmd_type").map(|s| s.as_str()) {
                    Some(CMD_GIT_TOPLEVEL) => self.handle_git_toplevel(exit_code, &stdout, &stderr),
                    Some(CMD_LIST_WORKTREES) => self.handle_list_worktrees(exit_code, &stdout),
                    Some(CMD_GIT_BRANCHES) => self.handle_git_branches(exit_code, &stdout),
                    Some(CMD_SPAWN) => self.handle_spawn_result(exit_code, &stderr, &context),
                    Some(CMD_REMOVE) => self.handle_remove_result(exit_code, &stderr, &context),
                    _ => {}
                }
                true
            }
            Event::Key(key) => {
                match self.mode {
                    Mode::Loading => {}
                    Mode::BrowseWorktrees => self.handle_key_browse(&key),
                    Mode::SelectBranch => self.handle_key_select_branch(&key),
                    Mode::InputBranch => self.handle_key_input_branch(&key),
                    Mode::Confirming => self.handle_key_confirming(&key),
                }
                true
            }
            _ => false,
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        match self.mode {
            Mode::Loading => {
                ui::render_header("loading...", cols);
                println!();
                println!("  Waiting for permissions...");
            }
            Mode::BrowseWorktrees => {
                ui::render_header(&self.repo_name, cols);
                ui::render_worktree_list(&self.worktrees, self.selected_index, rows);
                ui::render_status(&self.status_message, self.status_is_error);
                ui::render_footer(&self.mode);
            }
            Mode::SelectBranch => {
                ui::render_header(&self.repo_name, cols);
                ui::render_branch_list(&self.filtered_branches, self.selected_index, rows);
                ui::render_footer(&self.mode);
            }
            Mode::InputBranch => {
                ui::render_header(&self.repo_name, cols);
                ui::render_input(&self.input_buffer);
                ui::render_footer(&self.mode);
            }
            Mode::Confirming => {
                ui::render_header(&self.repo_name, cols);
                if let Some(wt) = self.worktrees.get(self.selected_index) {
                    ui::render_confirm(&wt.branch);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_worktrees_filters_by_prefix() {
        let output = "\
worktree /Users/me/code/myrepo
HEAD abc123
branch refs/heads/main

worktree /Users/me/.spawn-agent/myrepo/feature/cool
HEAD def456
branch refs/heads/feature/cool

worktree /Users/me/.spawn-agent/myrepo/fix-bug
HEAD 789abc
branch refs/heads/fix-bug

worktree /Users/me/.spawn-agent/other-repo/feature/cool
HEAD 111222
branch refs/heads/feature/cool
";
        let prefix = "/Users/me/.spawn-agent/myrepo/";
        let wts = parse_worktrees(output, prefix);

        assert_eq!(wts.len(), 2);
        assert_eq!(wts[0].branch, "feature/cool");
        assert_eq!(wts[0].path, "/Users/me/.spawn-agent/myrepo/feature/cool");
        assert_eq!(wts[1].branch, "fix-bug");
    }

    #[test]
    fn parse_worktrees_empty_output() {
        let wts = parse_worktrees("", "/some/prefix/");
        assert!(wts.is_empty());
    }

    #[test]
    fn parse_worktrees_bare_entry_skipped() {
        let output = "\
worktree /Users/me/code/myrepo
HEAD abc123
branch refs/heads/main

worktree /Users/me/.spawn-agent/myrepo/dev
HEAD def456
bare
";
        let wts = parse_worktrees(output, "/Users/me/.spawn-agent/myrepo/");
        assert!(wts.is_empty());
    }

    #[test]
    fn parse_branches_basic() {
        let output = "main\nfeature/cool\nfix-bug\n";
        let branches = parse_branches(output);
        assert_eq!(branches, vec!["main", "feature/cool", "fix-bug"]);
    }

    #[test]
    fn parse_branches_strips_whitespace_and_empty() {
        let output = "  main \n\n  dev  \n";
        let branches = parse_branches(output);
        assert_eq!(branches, vec!["main", "dev"]);
    }

}
