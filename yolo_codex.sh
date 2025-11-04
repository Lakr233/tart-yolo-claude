#!/bin/zsh

set -euo pipefail

DROP_TO_SHELL=false
if [[ "$#" -gt 0 ]] && [[ "$1" == "--drop-to-shell" ]]; then
    DROP_TO_SHELL=true
fi

source "$(dirname "$0")/yolo_tart_exec.sh"
TART_IMAGE="tart_yolo_base"
RUNNER_IMAGE_NAME="yolo-codex-runner-${RANDOM}"

check_dependencies
prepare_image
setup_cleanup_traps
start_vm

echo "[*] uploading codex configuration..."
CODEX_CONFIGURATIONS=(
    "${HOME}/.codex"
    "${HOME}/.codex.json"
)
for CONFIGURATION in "${CODEX_CONFIGURATIONS[@]}"; do
    if [ -e "$CONFIGURATION" ]; then
        echo "[*] found configuration: $CONFIGURATION"
        execute_runner_upload "$CONFIGURATION" "/Users/$RUNNER_USERNAME/"
    fi
done

if [ "$DROP_TO_SHELL" = true ]; then
    echo "[*] dropping to interactive shell..."
    RUNNER_CODEX_COMMAND="cd ~/projects && exec zsh -l"
    echo "[*] executing: $RUNNER_CODEX_COMMAND"
    execute_runner_command "$RUNNER_CODEX_COMMAND"
else
    setup_api_keys
    echo "[*] starting yolo-codex..."
    RUNNER_CODEX_COMMAND="cd ~/projects && codex"
    echo "[*] executing: $RUNNER_CODEX_COMMAND"
    execute_runner_command "$RUNNER_CODEX_COMMAND"
fi
