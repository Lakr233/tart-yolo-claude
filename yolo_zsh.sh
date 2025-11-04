#!/bin/zsh

set -euo pipefail

: ${BOOT_COMMAND:=""}
: ${MOUNT_PROJECT:="$(pwd)"}

while [[ $# -gt 0 ]]; do
    case $1 in
        --boot-command)
            BOOT_COMMAND="$2"
            shift 2
            ;;
        --mount-project)
            MOUNT_PROJECT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--boot-command <command>] [--mount <directory>]"
            exit 1
            ;;
    esac
done

export TART_IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-xcode:latest}"
export RUNNER_IMAGE_NAME="${RUNNER_IMAGE_NAME:-yolo-zsh-runner-${RANDOM}}"
export MOUNT_PROJECT

source "$(dirname "$0")/yolo_tart_exec.sh"

check_dependencies
prepare_image
start_vm

setup_cleanup_traps() {
    trap cleanup INT
    trap cleanup TERM
}
setup_cleanup_traps

if declare -f vm_bootstrap > /dev/null; then
    echo "[*] running vm_bootstrap function..."
    vm_bootstrap
fi

if [ -z "$BOOT_COMMAND" ]; then
    echo "[*] dropping into interactive zsh session..."
    execute_runner_command "exec zsh -l"
else
    echo "[*] executing boot command..."
    execute_runner_command "$BOOT_COMMAND"
fi

echo "[*] session exited, cleaning up..."
cleanup
