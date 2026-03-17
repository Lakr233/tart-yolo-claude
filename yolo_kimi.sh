#!/bin/zsh

set -euo pipefail

if [[ "$0" == */* ]]; then
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
	SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
fi

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-kimi-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"
RUNNER_UPLOAD_EXCLUDES=(
	".kimi/logs"
	".kimi/sessions"
	".kimi/user-history"
)

vm_bootstrap() {
	echo "[*] uploading kimi configuration..."
	execute_runner_upload_batch "/Users/$RUNNER_USERNAME" \
		"${HOME}/.kimi" \
		"${HOME}/.kimi.json"

	execute_runner_export_envs "API_KEY"
}

# uv tool installs typically expose a shim in ~/.local/bin.
export BOOT_COMMAND='cd ~/project && kimi --yolo; exec zsh -l'

source "$SCRIPT_DIR/yolo_zsh.sh"
