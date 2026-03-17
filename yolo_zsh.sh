#!/bin/zsh

set -euo pipefail

if [[ -z "${SCRIPT_DIR:-}" ]]; then
	if [[ "$0" == */* ]]; then
		SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
	else
		SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
	fi
fi

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

export TART_IMAGE="${TART_IMAGE:-tart_yolo_base}"
export RUNNER_IMAGE_NAME="${RUNNER_IMAGE_NAME:-yolo-zsh-runner-${RANDOM}}"
export MOUNT_PROJECT

source "$SCRIPT_DIR/yolo_tart_exec.sh"
setup_cleanup

check_dependencies
prepare_image
start_vm

if declare -f vm_bootstrap >/dev/null; then
	echo "[*] running vm_bootstrap function..."
	vm_bootstrap
fi

if [ -z "$BOOT_COMMAND" ]; then
	echo "[*] dropping into interactive zsh session..."
	execute_runner_command "cd project && exec zsh -l"
else
	echo "[*] executing boot command..."
	execute_runner_command "$BOOT_COMMAND"
fi

echo "[*] session exited, cleaning up..."
if cleanup; then
	clear_cleanup_traps
fi
