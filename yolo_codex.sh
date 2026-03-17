#!/bin/zsh

set -euo pipefail

if [[ "$0" == */* ]]; then
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
	SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
fi

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-codex-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"

vm_bootstrap() {
	echo "[*] uploading codex configuration..."
	execute_runner_upload_batch "/Users/$RUNNER_USERNAME" \
		"${HOME}/.codex" \
		"${HOME}/.codex.json"

	execute_runner_export_envs "API_KEY"
}

export BOOT_COMMAND="cd ~/project && codex --yolo; exec zsh -l"

source "$SCRIPT_DIR/yolo_zsh.sh"
