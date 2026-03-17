#!/bin/zsh

set -euo pipefail

if [[ "$0" == */* ]]; then
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
	SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
fi

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-opencode-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"
RUNNER_UPLOAD_EXCLUDES=(
	".opencode/history"
	".opencode/logs"
	".opencode/sessions"
	".opencode/tmp"
)

vm_bootstrap() {
	echo "[*] uploading opencode configuration..."
	execute_runner_upload_batch "/Users/$RUNNER_USERNAME" \
		"${HOME}/.opencode" \
		"${HOME}/.opencode.json"

	execute_runner_export_envs "API_KEY"
}

# opencode binary name may vary; try common ones.
export BOOT_COMMAND='cd ~/project && export OPENCODE_YOLO=true && opencode; exec zsh -l'

source "$SCRIPT_DIR/yolo_zsh.sh"
