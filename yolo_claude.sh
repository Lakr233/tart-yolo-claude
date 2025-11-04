#!/bin/zsh

set -euo pipefail

DROP_TO_SHELL=false
if [[ "$#" -gt 0 ]] && [[ "$1" == "--drop-to-shell" ]]; then
    DROP_TO_SHELL=true
fi

# Source the VM runner script
source "$(dirname "$0")/yolo_vm_run.sh"

# Configure specific settings for yolo_claude
TART_IMAGE="tart_yolo_base"
RUNNER_IMAGE_NAME="yolo-claude-runner-${RANDOM}"

# Run the VM setup
check_dependencies
prepare_image
setup_cleanup_traps
start_vm

echo "[*] uploading claude configuration..."
CONFIGURATIONS=(
    "${HOME}/.claude"
    "${HOME}/.claude.json"
)
for CONFIGURATION in "${CONFIGURATIONS[@]}"; do
    if [ -e "$CONFIGURATION" ]; then
        echo "[*] found configuration: $CONFIGURATION"
        execute_runner_upload "$CONFIGURATION" "/Users/$RUNNER_USERNAME/"
    fi
done

if [ "$DROP_TO_SHELL" = true ]; then
    echo "[*] dropping to interactive shell..."
    RUNNER_YOLO_COMMAND="cd ~/projects && exec zsh -l"
    echo "[*] executing: $RUNNER_YOLO_COMMAND"
    execute_runner_command "$RUNNER_YOLO_COMMAND"
else
    setup_api_keys
    echo "[*] starting yolo-claude..."
    RUNNER_YOLO_COMMAND="cd ~/projects && claude --dangerously-skip-permissions"
    echo "[*] executing: $RUNNER_YOLO_COMMAND"
    execute_runner_command "$RUNNER_YOLO_COMMAND"
fi
