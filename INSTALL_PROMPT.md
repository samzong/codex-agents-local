# Install Prompt

Copy this prompt into Codex:

```text
Please install codex-agents-local for me.

Repo: https://github.com/samzong/codex-agents-local

Goals:
- Install `codex-agents-local` into `~/.local/bin`.
- Update `~/.codex/hooks.json` and enable the `SessionStart` and `UserPromptSubmit` hooks.
- Do not replace, move, overwrite, or alias my existing `codex` command.
- After installation, I should keep using the official `codex` command and Codex IDE/desktop with no launch-path changes.
- Do not enable the `PreToolUse` hook unless I explicitly ask for stronger long-session sync.
- Run `codex-agents-local doctor` after installation.
- If `~/.local/bin` is not in PATH, tell me the exact line I should add, but do not edit my shell profile automatically.
- Finish with a short summary covering the install path, whether hooks were written, whether `codex` was changed, and whether CLI and Codex IDE/desktop still use their original entry points.

You may execute these steps directly:

1. Create a temporary directory.
2. `git clone --depth 1 https://github.com/samzong/codex-agents-local.git`
3. Enter the repo and briefly inspect `install.sh` and `bin/codex-agents-local` to confirm the default install only writes `~/.local/bin/codex-agents-local` and `~/.codex/hooks.json`.
4. Run `sh install.sh`.
5. Run `~/.local/bin/codex-agents-local doctor`.
6. Do not commit, push, or modify any project repository files.
```
