#!/bin/zsh

set -euo pipefail

if [[ "$0" == */* ]]; then
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
	SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
fi

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-claude-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"

source "$SCRIPT_DIR/yolo_tart_exec.sh"

setup_cleanup() {
	echo "[*] setting up main cleanup trap..."
	trap cleanup EXIT INT TERM HUP ERR
}
setup_cleanup

vm_bootstrap() {
	echo "[*] uploading claude configuration..."
	execute_runner_upload_batch "/Users/$RUNNER_USERNAME" \
		"${HOME}/.claude" \
		"${HOME}/.claude.json"

	execute_runner_export_envs "API_KEY"
}

export BOOT_COMMAND="cd ~/project && claude --dangerously-skip-permissions; exec zsh -l"

source "$SCRIPT_DIR/yolo_zsh.sh"
