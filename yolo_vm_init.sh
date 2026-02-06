#!/bin/zsh

set -euo pipefail

ensure_line_in_file() {
	local line="$1"
	local file="$2"
	mkdir -p "$(dirname "$file")" 2>/dev/null || true
	touch "$file"
	if ! grep -qxF "$line" "$file"; then
		echo "$line" >>"$file"
	fi
}

echo "[*] yolo_vm_init: starting..."

ensure_line_in_file 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' "$HOME/.zshenv"
ensure_line_in_file 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.zshenv"
ensure_line_in_file 'export PNPM_HOME=$HOME/Library/pnpm' "$HOME/.zshenv"
ensure_line_in_file 'export PATH=$PNPM_HOME:$PATH' "$HOME/.zshenv"

source "$HOME/.zshenv"

export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_UPGRADE=1

echo "[*] installing base development tools (brew)..."
brew update
brew install --force --overwrite \
	git curl wget htop vim nano jq yq coreutils tmux \
	python@3.13 \
	swiftformat xcbeautify \
	node \
	uv

if ! command -v node >/dev/null 2>&1; then
	echo "[-] node not found after brew install node" >&2
	exit 1
fi

PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
mkdir -p "$PNPM_HOME"
export PNPM_HOME
export PATH="$PNPM_HOME:$PATH"

if command -v corepack >/dev/null 2>&1; then
	echo "[*] enabling corepack/pnpm..."
	corepack enable || true
	corepack prepare pnpm@latest --activate || true
fi

if ! command -v pnpm >/dev/null 2>&1; then
	if ! command -v npm >/dev/null 2>&1; then
		echo "[-] neither pnpm nor npm is available" >&2
		exit 1
	fi
	echo "[*] pnpm not found; installing pnpm via npm..."
	npm i -g pnpm
fi

PNPM_GLOBAL_DIR="$HOME/Library/pnpm/global"
mkdir -p "$PNPM_GLOBAL_DIR"

echo "[*] configuring pnpm global dirs..."
pnpm config set global-bin-dir "$PNPM_HOME"
pnpm config set global-dir "$PNPM_GLOBAL_DIR"

PNPM_GLOBAL_BIN_DIR="$(pnpm config get global-bin-dir || true)"
if [[ -z "$PNPM_GLOBAL_BIN_DIR" ]]; then
	echo "[-] pnpm global-bin-dir is empty after configuration" >&2
	exit 1
fi
case ":$PATH:" in
	*":$PNPM_GLOBAL_BIN_DIR:"*) ;;
	*)
		echo "[-] pnpm global bin dir is not in PATH: $PNPM_GLOBAL_BIN_DIR" >&2
		echo "[-] PATH is: $PATH" >&2
		exit 1
		;;
esac

echo "[*] installing/updating Claude Code (native install)..."
curl -fsSL https://claude.ai/install.sh | bash

echo "[*] installing/updating OpenCode (native install)..."
curl -fsSL https://opencode.ai/install | bash

echo "[*] installing/updating Codex and Gemini CLI via pnpm..."
pnpm add -g \
	@openai/codex@latest \
	@google/gemini-cli@latest

if ! command -v uv >/dev/null 2>&1; then
	echo "[-] uv not found after installation" >&2
	exit 1
fi

echo "[*] installing/updating Kimi CLI via uv..."
uv python install 3.13
uv tool install --python 3.13 kimi-cli || uv tool upgrade kimi-cli

echo "[*] installing/updating ralph-claude-code..."
RALPH_DIR="$HOME/.ralph-claude-code"
if [[ -d "$RALPH_DIR" ]]; then
	echo "[*] ralph-claude-code already cloned, pulling latest..."
	git -C "$RALPH_DIR" pull || true
else
	git clone https://github.com/frankbria/ralph-claude-code.git "$RALPH_DIR"
fi
(cd "$RALPH_DIR" && bash install.sh)

echo "[*] cleaning up..."
brew cleanup || true

echo "[*] yolo_vm_init completed"
