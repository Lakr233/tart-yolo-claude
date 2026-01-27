#!/bin/zsh

set -euo pipefail

MODE="init" # init|update

usage() {
	cat <<EOF
Usage: $0 [--mode init|update]

This script is intended to run INSIDE the VM.
The host-side launcher should upload it to the VM, then execute it.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--mode)
		MODE="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [[ "$MODE" != "init" && "$MODE" != "update" ]]; then
	echo "[-] invalid --mode: $MODE (expected init|update)" >&2
	exit 1
fi

ensure_line_in_file() {
	local line="$1"
	local file="$2"
	mkdir -p "$(dirname "$file")" 2>/dev/null || true
	touch "$file"
	if ! grep -qxF "$line" "$file"; then
		echo "$line" >>"$file"
	fi
}

echo "[*] yolo_vm_init: mode=$MODE"

# Ensure common PATH entries exist for both brew and uv tool shims.
ensure_line_in_file 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' "$HOME/.zprofile"
ensure_line_in_file 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.zprofile"
ensure_line_in_file 'export PNPM_HOME=$HOME/Library/pnpm' "$HOME/.zprofile"
ensure_line_in_file 'export PATH=$PNPM_HOME:$PATH' "$HOME/.zprofile"
ensure_line_in_file '[[ -f $HOME/.zshrc ]] && source $HOME/.zshrc' "$HOME/.zprofile"
touch "$HOME/.zshrc"

# Make PATH effective for this non-interactive run as well.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

BREW_BIN=""
if command -v brew >/dev/null 2>&1; then
	BREW_BIN="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
	BREW_BIN="/opt/homebrew/bin/brew"
fi

if [[ -z "$BREW_BIN" ]]; then
	echo "[-] Homebrew not found inside VM. Please ensure the base image has brew." >&2
	exit 1
fi

export HOMEBREW_NO_ENV_HINTS=1

if [[ "$MODE" == "init" ]]; then
	echo "[*] installing base development tools (brew)..."
	"$BREW_BIN" update

	# Avoid incidental upgrades that can fail on unrelated formulae.
	HOMEBREW_NO_INSTALL_UPGRADE=1 "$BREW_BIN" install --force --overwrite \
		git curl wget htop vim nano jq yq coreutils \
		python@3.13 \
		swiftformat xcbeautify \
		node \
		uv

	# Keep init stable; do not upgrade the whole brew set here.
else
	echo "[*] updating brew packages..."
	"$BREW_BIN" update
	"$BREW_BIN" upgrade --overwrite || true
fi

if ! command -v node >/dev/null 2>&1; then
	echo "[-] node not found after brew install node" >&2
	exit 1
fi

# pnpm global installs require a global bin dir (PNPM_HOME) on PATH.
PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
mkdir -p "$PNPM_HOME"
export PNPM_HOME
export PATH="$PNPM_HOME:$PATH"

# Prefer pnpm (via corepack) for global CLI installs.
# Fall back to npm->pnpm if corepack is unavailable for some reason.
if command -v corepack >/dev/null 2>&1; then
	echo "[*] enabling corepack/pnpm..."
	corepack enable || true
	# Try to activate latest pnpm.
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

echo "[*] installing/updating global CLIs via pnpm..."
# Requested packages:
# - @anthropic-ai/claude-code@latest
# - @openai/codex@latest
# - @google/gemini-cli@latest
# - opencode-ai
pnpm add -g \
	@anthropic-ai/claude-code@latest \
	@openai/codex@latest \
	@google/gemini-cli@latest \
	opencode-ai

if ! command -v uv >/dev/null 2>&1; then
	echo "[-] uv not found after installation" >&2
	exit 1
fi

echo "[*] installing/updating kimi via uv (uv must be installed first)..."
uv python install 3.13
uv tool install --python 3.13 kimi-cli || uv tool upgrade kimi-cli

echo "[*] cleaning up..."
"$BREW_BIN" cleanup || true

echo "[*] yolo_vm_init completed"
