#!/bin/zsh

set -euo pipefail

PREPARED_IMAGE_NAME="tart_yolo_base"
RUNNER_USERNAME="admin"
RUNNER_PASSWORD="admin"
RUNNER_IP=""

check_dependencies() {
	if ! command -v tart &>/dev/null; then
		echo "[-] tart could not be found"
		exit 1
	fi

	if ! command -v sshpass &>/dev/null; then
		echo "[-] sshpass could not be found"
		exit 1
	fi
}

ensure_image_exists() {
	if ! echo $(tart list || true) | grep -q "$PREPARED_IMAGE_NAME"; then
		echo "[-] image $PREPARED_IMAGE_NAME does not exist"
		echo "[-] run yolo_tart_prepare.sh first"
		exit 1
	fi
}

CLEANUP_DONE=false
function cleanup {
	if [ "$CLEANUP_DONE" = false ]; then
		echo "[*] cleaning up..."
		tart stop "$PREPARED_IMAGE_NAME" || true
		wait
		CLEANUP_DONE=true
	fi
}

function execute_vm_command() {
	local CMD="$1"

	local MAX_ATTEMPTS=3
	local ATTEMPT=1
	local EXIT_CODE=0
	while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
		if sshpass -p "$RUNNER_PASSWORD" \
			ssh -o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o PreferredAuthentications=password \
			-o ConnectTimeout=10 \
			-t \
			"$RUNNER_USERNAME@$RUNNER_IP" "source ~/.zprofile && $CMD"; then
			return 0
		fi

		EXIT_CODE=$?
		if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
			echo "[!] execute_vm_command failed (attempt $ATTEMPT/$MAX_ATTEMPTS), retrying..." >&2
			sleep 2
		fi
		ATTEMPT=$((ATTEMPT + 1))
	done

	echo "[-] execute_vm_command failed after $MAX_ATTEMPTS attempts: $CMD" >&2
	return $EXIT_CODE
}

function execute_vm_init() {
	local MODE="$1" # init|update
	local INIT_LOCAL="$(dirname "$0")/yolo_vm_init.sh"

	echo "[*] uploading and running yolo_vm_init.sh inside VM (mode=$MODE)..."

	local MAX_ATTEMPTS=3
	local ATTEMPT=1
	local EXIT_CODE=0
	while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
		if sshpass -p "$RUNNER_PASSWORD" \
			ssh -o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null \
			-o PreferredAuthentications=password \
			-o ConnectTimeout=10 \
			"$RUNNER_USERNAME@$RUNNER_IP" \
			"zsh -lc 'cat > ~/yolo_vm_init.sh && chmod +x ~/yolo_vm_init.sh && ~/yolo_vm_init.sh --mode $MODE'" \
			<"$INIT_LOCAL"; then
			return 0
		fi

		EXIT_CODE=$?
		if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
			echo "[!] execute_vm_init failed (attempt $ATTEMPT/$MAX_ATTEMPTS), retrying..." >&2
			sleep 2
		fi
		ATTEMPT=$((ATTEMPT + 1))
	done

	echo "[-] execute_vm_init failed after $MAX_ATTEMPTS attempts" >&2
	return $EXIT_CODE
}

start_vm() {
	echo "[*] starting vm for update..."

	TART_PARMS=()
	if [ -n "${MOUNT_PROJECT:-}" ] && [ -d "$MOUNT_PROJECT" ]; then
		echo "[*] mounting project directory: $MOUNT_PROJECT"
		TART_PARMS+=("--dir=project:$MOUNT_PROJECT")
	fi
	TART_PARMS+=("--no-audio" "--no-clipboard")

	tart run "$PREPARED_IMAGE_NAME" "${TART_PARMS[@]}" &

	echo "[*] waiting for vm to start..."
	RUNNER_BOOT_ATTEMPTS=0
	while [ -z "$RUNNER_IP" ] && [ $RUNNER_BOOT_ATTEMPTS -lt 30 ]; do
		sleep 3
		RUNNER_BOOT_ATTEMPTS=$((RUNNER_BOOT_ATTEMPTS + 1))
		RUNNER_IP=$(tart ip "$PREPARED_IMAGE_NAME" || true)
	done

	if [ -z "$RUNNER_IP" ]; then
		echo "[-] failed to get vm ip address"
		exit 1
	fi

	echo "[*] vm ip address: $RUNNER_IP"
	echo "[*] waiting for ssh connectivity..."
	SSH_ATTEMPTS=0
	while [ $SSH_ATTEMPTS -lt 30 ]; do
		if execute_vm_command "echo hello" &>/dev/null; then
			break
		fi
		sleep 2
		SSH_ATTEMPTS=$((SSH_ATTEMPTS + 1))
	done

	if [ $SSH_ATTEMPTS -eq 30 ]; then
		echo "[-] failed to establish ssh connectivity"
		exit 1
	fi
}

update_dev_tools() {
	execute_vm_init "update"
}

main() {
	echo "[*] starting yolo tart update..."

	trap cleanup EXIT INT TERM HUP ERR

	check_dependencies
	ensure_image_exists
	start_vm
	update_dev_tools

	echo "[*] stopping vm..."
	tart stop "$PREPARED_IMAGE_NAME"

	echo "[*] yolo tart update completed successfully!"
	CLEANUP_DONE=true
}

main "$@"
