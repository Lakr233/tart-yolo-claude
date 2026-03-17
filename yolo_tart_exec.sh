#!/bin/zsh

set -euo pipefail

: ${TART_IMAGE:="ghcr.io/cirruslabs/macos-tahoe-xcode:latest"}
: ${RUNNER_IMAGE_NAME:="yolo-runner-${RANDOM}"}
: ${RUNNER_USERNAME:="admin"}
: ${RUNNER_PASSWORD:="admin"}
: ${RUNNER_IP:=""}
: ${RUNNER_PROJECT_MOUNT:="/Volumes/My Shared Files/project"}

setup_cleanup() {
	echo "[*] setting up cleanup trap..."
	trap cleanup EXIT INT TERM HUP
}

clear_cleanup_traps() {
	trap - EXIT INT TERM HUP
}

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

prepare_image() {
	if echo $(tart list || true) | grep -q "$TART_IMAGE"; then
		echo "[*] runner image $TART_IMAGE already exists"
	else
		echo "[*] runner image $TART_IMAGE does not exist, pulling..."
		tart pull "$TART_IMAGE"
	fi

	echo "[*] using runner image name: $RUNNER_IMAGE_NAME"
	tart clone "$TART_IMAGE" "$RUNNER_IMAGE_NAME"
}

CLEANUP_DONE=false
CLEANUP_IN_PROGRESS=false
runner_image_exists() {
	tart list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -Fxq "$RUNNER_IMAGE_NAME"
}

function cleanup {
	if [ "$CLEANUP_DONE" = true ]; then
		return 0
	fi

	if [ "$CLEANUP_IN_PROGRESS" = true ]; then
		return 0
	fi

	CLEANUP_IN_PROGRESS=true
	echo "[*] cleaning up runner image $RUNNER_IMAGE_NAME..."

	if ! runner_image_exists; then
		echo "[*] runner image $RUNNER_IMAGE_NAME already removed"
		CLEANUP_DONE=true
		CLEANUP_IN_PROGRESS=false
		return 0
	fi

	tart stop "$RUNNER_IMAGE_NAME" &>/dev/null || true

	local DELETE_ATTEMPT=1
	local MAX_DELETE_ATTEMPTS=15
	while [ $DELETE_ATTEMPT -le $MAX_DELETE_ATTEMPTS ]; do
		if ! runner_image_exists; then
			echo "[*] runner image $RUNNER_IMAGE_NAME is gone"
			CLEANUP_DONE=true
			CLEANUP_IN_PROGRESS=false
			return 0
		fi

		if tart delete "$RUNNER_IMAGE_NAME" &>/dev/null; then
			echo "[*] deleted runner image $RUNNER_IMAGE_NAME"
			CLEANUP_DONE=true
			CLEANUP_IN_PROGRESS=false
			return 0
		fi

		echo "[*] runner image $RUNNER_IMAGE_NAME still busy, retrying delete ($DELETE_ATTEMPT/$MAX_DELETE_ATTEMPTS)..."
		sleep 2
		tart stop "$RUNNER_IMAGE_NAME" &>/dev/null || true
		DELETE_ATTEMPT=$((DELETE_ATTEMPT + 1))
	done

	echo "[!] failed to delete runner image $RUNNER_IMAGE_NAME after $MAX_DELETE_ATTEMPTS attempts" >&2
	CLEANUP_IN_PROGRESS=false
	return 1
}

function execute_runner_command() {
	local CMD="$1"
	echo "[*] executing on runner: $CMD"
	sshpass -p "$RUNNER_PASSWORD" \
		ssh -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o PreferredAuthentications=password \
		-o ConnectTimeout=30 \
		-t \
		"$RUNNER_USERNAME@$RUNNER_IP" "[[ -f ~/.zshenv ]] && source ~/.zshenv; $CMD"
}

function execute_runner_upload() {
	local SRC="$1"
	local DEST="$2"
	echo "[*] uploading $SRC to $DEST"
	sshpass -p "$RUNNER_PASSWORD" \
		scp -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o PreferredAuthentications=password \
		-o ConnectTimeout=30 \
		-r "$SRC" \
		"$RUNNER_USERNAME@$RUNNER_IP:$DEST"
}

# Batch upload: tar files locally, scp one archive, extract on VM.
# Usage: execute_runner_upload_batch <dest_base_dir> <file1> [file2 ...]
# Files are tarred relative to $HOME and extracted into dest_base_dir.
function execute_runner_upload_batch() {
	local DEST_BASE="$1"
	shift
	local FILES_TO_TAR=()
	for SRC in "$@"; do
		if [ -e "$SRC" ]; then
			# Get path relative to $HOME
			local REL="${SRC#$HOME/}"
			FILES_TO_TAR+=("$REL")
			echo "[*] found configuration: $SRC"
		fi
	done

	if [ ${#FILES_TO_TAR[@]} -eq 0 ]; then
		echo "[*] no configuration files to upload"
		return
	fi

	local TAR_FILE="/tmp/yolo_upload_$$.tar.gz"
	echo "[*] creating archive with ${#FILES_TO_TAR[@]} item(s)..."
	tar -czf "$TAR_FILE" -C "$HOME" "${FILES_TO_TAR[@]}"

	echo "[*] uploading archive to VM..."
	sshpass -p "$RUNNER_PASSWORD" \
		scp -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		-o PreferredAuthentications=password \
		-o ConnectTimeout=30 \
		"$TAR_FILE" \
		"$RUNNER_USERNAME@$RUNNER_IP:/tmp/yolo_upload.tar.gz"

	echo "[*] extracting archive on VM..."
	execute_runner_command "tar -xzf /tmp/yolo_upload.tar.gz -C '$DEST_BASE' && rm -f /tmp/yolo_upload.tar.gz"

	rm -f "$TAR_FILE"
}

# Batch export environment variables matching a pattern to VM's ~/.zshenv.
# Usage: execute_runner_export_envs <pattern>
# Example: execute_runner_export_envs "API_KEY"
function execute_runner_export_envs() {
	local PATTERN="$1"
	local ENV_EXPORTS=""
	for ENV_KEY in $(printenv | cut -d= -f1); do
		if [[ "$ENV_KEY" == *"$PATTERN"* ]]; then
			local ENV_VALUE=$(printenv "$ENV_KEY")
			echo "[*] adding environment variable $ENV_KEY to runner"
			ENV_EXPORTS+="export $ENV_KEY=\"$ENV_VALUE\""$'\n'
		fi
	done

	if [ -n "$ENV_EXPORTS" ]; then
		execute_runner_command "cat >> ~/.zshenv <<'ENVEOF'
${ENV_EXPORTS}ENVEOF"
	fi
}

start_vm() {
	local MOUNT_PATH="${MOUNT_DIR:-$(pwd)}"
	echo "[*] starting runner image, mounting dir $MOUNT_PATH..."

	if ! tart list | grep -q "$RUNNER_IMAGE_NAME"; then
		echo "[-] Error: Runner VM '$RUNNER_IMAGE_NAME' does not exist"
		exit 1
	fi

	tart run "$RUNNER_IMAGE_NAME" \
		--dir=project:"$MOUNT_PATH" \
		--no-audio \
		--no-clipboard \
		& # detach

	echo "[*] waiting for runner image to start..."
	RUNNER_BOOT_ATTEMPTS=0
	while [ -z "$RUNNER_IP" ] && [ $RUNNER_BOOT_ATTEMPTS -lt 30 ]; do
		sleep 2
		echo "[*] checking for runner ip address..."
		RUNNER_BOOT_ATTEMPTS=$((RUNNER_BOOT_ATTEMPTS + 1))
		RUNNER_IP=$(tart ip "$RUNNER_IMAGE_NAME" 2>/dev/null || true)
	done

	if [ -z "$RUNNER_IP" ]; then
		echo "[-] Error: Failed to get IP address for VM '$RUNNER_IMAGE_NAME' after 30 attempts"
		echo "[-] VM may have failed to start properly"
		exit 1
	fi

	echo "[*] runner ip address: $RUNNER_IP"
	while [ $RUNNER_BOOT_ATTEMPTS -lt 60 ]; do # another 30 attempts to connect via ssh
		echo "[*] checking for ssh connectivity to $RUNNER_IP..."
		if execute_runner_command "echo hello" &>/dev/null; then
			echo "[*] ssh connectivity to $RUNNER_IP established"
			break
		fi
		echo "[*] ssh connectivity to $RUNNER_IP not yet established, waiting..."
		sleep 2
		RUNNER_BOOT_ATTEMPTS=$((RUNNER_BOOT_ATTEMPTS + 1))
	done

	if [ $RUNNER_BOOT_ATTEMPTS -ge 60 ]; then
		echo "[-] Error: Failed to establish SSH connectivity to $RUNNER_IP after 60 attempts"
		exit 1
	fi

	echo "[*] ensuring ~/project points to mounted directory..."
	execute_runner_command "ln -sfn '$RUNNER_PROJECT_MOUNT' ~/project"
}
