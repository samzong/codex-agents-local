#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'audit failed: %s\n' "$1" >&2
  exit 1
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

need git
need python3
need rg
need shellcheck

printf '==> shell syntax\n'
find install.sh hooks scripts -type f -print0 | xargs -0 -n 1 sh -n

printf '==> shellcheck\n'
find install.sh hooks scripts -type f -print0 | xargs -0 shellcheck

printf '==> python compile\n'
python3 -m py_compile bin/codex-agents-local

printf '==> python unit tests\n'
python3 -m unittest discover -s tests

printf '==> no CJK project text\n'
if rg -n '[\p{Han}]' --glob '!.git/**' .; then
  fail "CJK text found in project files"
fi

printf '==> dangerous shell patterns\n'
if rg -n \
  -e '(^|[;&|[:space:]])eval([[:space:]]|$)' \
  -e '(^|[;&|[:space:]])source[[:space:]]' \
  -e '(^|[;&|[:space:]])\.[[:space:]]+[^/]' \
  -e 'curl[^\n|]*\|[^\n]*(sh|bash)' \
  -e '(sh|bash)[[:space:]]+-c[[:space:]]' \
  -e 'sudo[[:space:]]' \
  -e 'rm[[:space:]]+-rf[[:space:]]' \
  -e 'mktemp[[:space:]]+-u' \
  -e 'chmod[[:space:]]+777' \
  install.sh hooks; then
  fail "dangerous shell pattern found"
fi

printf '==> dangerous python patterns\n'
if rg -n \
  -e 'shell[[:space:]]*=[[:space:]]*True' \
  -e 'os\.system[[:space:]]*\(' \
  -e 'pickle\.loads[[:space:]]*\(' \
  -e 'yaml\.load[[:space:]]*\(' \
  -e 'eval[[:space:]]*\(' \
  bin/codex-agents-local; then
  fail "dangerous python pattern found"
fi

printf '==> temporary install\n'
tmp="$(mktemp -d)"
cleanup() {
  if [ -n "$tmp" ] && [ -d "$tmp" ]; then
    rm -R "$tmp"
  fi
}
trap cleanup EXIT HUP INT TERM
CODEX_HOME="$tmp/codex-home" INSTALL_DIR="$tmp/bin" sh install.sh >/dev/null
test -x "$tmp/bin/codex-agents-local"
test ! -e "$tmp/bin/codex-local"
test -f "$tmp/codex-home/hooks.json"

python3 - "$tmp/codex-home/hooks.json" <<'PY'
import json
import sys
from pathlib import Path

hooks = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["hooks"]
assert "SessionStart" in hooks, hooks
assert "UserPromptSubmit" in hooks, hooks
assert "PreToolUse" not in hooks, hooks
PY

printf '==> hook behavior\n'
repo="$tmp/repo"
mkdir -p "$repo/manual" "$repo/local-only"
git -C "$repo" init --quiet
printf 'base\n' > "$repo/AGENTS.md"
printf 'local\n' > "$repo/AGENTS.local.md"
printf 'manual override\n' > "$repo/manual/AGENTS.override.md"
printf 'manual local\n' > "$repo/manual/AGENTS.local.md"
printf 'local only\n' > "$repo/local-only/AGENTS.local.md"

CODEX_HOME="$tmp/codex-home" "$tmp/bin/codex-agents-local" hook session-start <<EOF > "$tmp/session-start.json"
{"cwd":"$repo","session_id":"audit-session"}
EOF

test -f "$repo/AGENTS.override.md"
test -f "$repo/local-only/AGENTS.override.md"
test "$(cat "$repo/manual/AGENTS.override.md")" = "manual override"
rg -q '"hookEventName":"SessionStart"' "$tmp/session-start.json"
rg -q 'manual/AGENTS.override.md already exists' "$tmp/session-start.json"

CODEX_HOME="$tmp/codex-home" "$tmp/bin/codex-agents-local" hook user-prompt-submit <<EOF > "$tmp/user-prompt.json"
{"cwd":"$repo","session_id":"audit-session"}
EOF

test "$(cat "$tmp/user-prompt.json")" = '{"continue":true,"suppressOutput":true}'

printf '==> symlink safety\n'
symlink_repo="$tmp/symlink-repo"
outside="$tmp/outside"
mkdir -p "$symlink_repo" "$outside"
git -C "$symlink_repo" init --quiet
printf 'outside secret\n' > "$outside/secret.txt"
ln -s "$outside/secret.txt" "$symlink_repo/AGENTS.local.md"

CODEX_HOME="$tmp/codex-home" "$tmp/bin/codex-agents-local" hook session-start <<EOF > "$tmp/symlink-local.json"
{"cwd":"$symlink_repo","session_id":"symlink-local"}
EOF

test ! -e "$symlink_repo/AGENTS.override.md"
rg -q 'AGENTS.local.md is not a regular file under' "$tmp/symlink-local.json"
if rg -q 'outside secret' "$tmp/symlink-local.json"; then
  fail "symlinked AGENTS.local.md leaked target contents"
fi

printf 'audit ok\n'
