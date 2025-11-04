#!/bin/zsh

set -euo pipefail

source "$(dirname "$0")/yolo_vm_run.sh"

TART_IMAGE="ghcr.io/cirruslabs/macos-tahoe-xcode:latest"
RUNNER_IMAGE_NAME="yolo-zsh-runner-${RANDOM}"

check_dependencies
prepare_image
setup_cleanup_traps
start_vm
setup_api_keys

echo "[*] starting interactive zsh session..."
echo "[*] project directory is available at ~/projects"
echo "[*] type 'exit' to quit and cleanup the runner"
RUNNER_ZSH_COMMAND="cd ~/projects && exec zsh -l"
echo "[*] executing: $RUNNER_ZSH_COMMAND"
execute_runner_command "$RUNNER_ZSH_COMMAND"
