#!/usr/bin/env sh
set -eu

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO="${REPO:-samzong/codex-agents-local}"
REF="${REF:-main}"
BASE_URL="${BASE_URL:-https://raw.githubusercontent.com/$REPO/$REF}"
SCRIPT_DIR="$(CDPATH=; cd -- "$(dirname -- "$0")" && pwd)"

mkdir -p "$INSTALL_DIR"
tmp=""

cleanup() {
  if [ -n "$tmp" ] && [ -d "$tmp" ]; then
    rm -R "$tmp"
  fi
}

download() {
  src="$1"
  dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
  else
    curl -fsSL "$BASE_URL/$src" -o "$dst"
  fi
  chmod +x "$dst"
}

if [ -f "$SCRIPT_DIR/bin/codex-agents-local" ]; then
  "$SCRIPT_DIR/bin/codex-agents-local" install --install-dir "$INSTALL_DIR" --hooks
else
  tmp="${TMPDIR:-/tmp}/codex-agents-local-install.$$"
  trap cleanup EXIT HUP INT TERM
  mkdir -p "$tmp/bin"
  download "bin/codex-agents-local" "$tmp/bin/codex-agents-local"
  "$tmp/bin/codex-agents-local" install --install-dir "$INSTALL_DIR" --hooks
fi

cat <<EOF

Installed codex-agents-local.

Add this to your global gitignore if it is not already present:

  AGENTS.local.md
  AGENTS.override.md

Use:

  codex .

Your existing codex command is unchanged. Direct codex and Codex IDE/desktop
sessions use the installed hooks when the Codex build loads ~/.codex/hooks.json.

EOF
