#!/bin/zsh

set -euo pipefail

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-opencode-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"

source "$(dirname "$0")/yolo_tart_exec.sh"

setup_cleanup() {
	echo "[*] setting up main cleanup trap..."
	trap cleanup EXIT INT TERM HUP ERR
}
setup_cleanup

vm_bootstrap() {
	echo "[*] uploading opencode configuration..."
	OPENCODE_CONFIGURATIONS=(
		"${HOME}/.opencode"
		"${HOME}/.opencode.json"
	)
	for CONFIGURATION in "${OPENCODE_CONFIGURATIONS[@]}"; do
		if [ -e "$CONFIGURATION" ]; then
			echo "[*] found configuration: $CONFIGURATION"
			execute_runner_upload "$CONFIGURATION" "/Users/$RUNNER_USERNAME/"
		fi
	done

	for ENV_KEY in $(printenv | cut -d= -f1); do
		if [[ "$ENV_KEY" == *"API_KEY"* ]]; then
			ENV_VALUE=$(printenv "$ENV_KEY")
			echo "[*] adding environment variable $ENV_KEY to runner"
			execute_runner_command "echo 'export $ENV_KEY=\"$ENV_VALUE\"' >> ~/.zshenv"
		fi
	done
}

# opencode binary name may vary; try common ones.
export BOOT_COMMAND='cd ~/projects && export OPENCODE_YOLO=true && opencode'

source "$(dirname "$0")/yolo_zsh.sh"
