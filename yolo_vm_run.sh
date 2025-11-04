#!/bin/zsh

set -euo pipefail

TART_IMAGE="${TART_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-xcode:latest}"
RUNNER_IMAGE_NAME="${RUNNER_IMAGE_NAME:-yolo-runner-${RANDOM}}"
RUNNER_USERNAME="admin"
RUNNER_PASSWORD="admin"
RUNNER_IP=""
RUNNER_PROJECT_MOUNT="/Volumes/My Shared Files/project"

check_dependencies() {
    if ! command -v tart &> /dev/null; then
        echo "[-] tart could not be found"
        exit 1
    fi

    if ! command -v sshpass &> /dev/null; then
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
function cleanup {
    if [ "$CLEANUP_DONE" = false ]; then
        echo "[*] cleaning up..."
        tart stop "$RUNNER_IMAGE_NAME" || true
        wait
        tart delete "$RUNNER_IMAGE_NAME" || true
        CLEANUP_DONE=true
    fi
}

setup_cleanup_traps() {
    trap cleanup EXIT
    trap cleanup INT
    trap cleanup TERM
    trap cleanup HUP
    trap cleanup ERR
}

function execute_runner_command() {
    local CMD="$1"
    echo "[*] executing on runner: $CMD"
    sshpass -p "$RUNNER_PASSWORD" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -t \
        "$RUNNER_USERNAME@$RUNNER_IP" "source ~/.zprofile && $CMD"
}

function execute_runner_upload() {
    local SRC="$1"
    local DEST="$2"
    echo "[*] uploading $SRC to $DEST"
    sshpass -p "$RUNNER_PASSWORD" \
        scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -r "$SRC" \
        "$RUNNER_USERNAME@$RUNNER_IP:$DEST"
}

start_vm() {
    echo "[*] starting runner image, mounting current dir $(pwd)..."
    tart run "$RUNNER_IMAGE_NAME" \
        --dir=project:$(pwd) \
        --no-graphics \
        --no-audio \
        --no-clipboard \
        & # detach

    echo "[*] waiting for runner image to start..."
    RUNNER_BOOT_ATTEMPTS=0
    while [ -z "$RUNNER_IP" ] && [ $RUNNER_BOOT_ATTEMPTS -lt 30 ]; do
        sleep 2
        echo "[*] checking for runner ip address..."
        RUNNER_BOOT_ATTEMPTS=$((RUNNER_BOOT_ATTEMPTS + 1))
        RUNNER_IP=$(tart ip "$RUNNER_IMAGE_NAME" || true)
    done

    echo "[*] runner ip address: $RUNNER_IP"
    while [ $RUNNER_BOOT_ATTEMPTS -lt 60 ]; do # another 30 attempts to connect via ssh
        echo "[*] checking for ssh connectivity to $RUNNER_IP..."
        if execute_runner_command "echo hello" &> /dev/null; then
            echo "[*] ssh connectivity to $RUNNER_IP established"
            break
        fi
        echo "[*] ssh connectivity to $RUNNER_IP not yet established, waiting..."
        sleep 2
        RUNNER_BOOT_ATTEMPTS=$((RUNNER_BOOT_ATTEMPTS + 1))
    done

    echo "[*] ensuring ~/projects points to mounted directory..."
    execute_runner_command "ln -sfn '$RUNNER_PROJECT_MOUNT' ~/projects"
}

setup_api_keys() {
    for ENV_KEY in $(printenv | cut -d= -f1); do
        if [[ "$ENV_KEY" == *"API_KEY"* ]]; then
            ENV_VALUE=$(printenv "$ENV_KEY")
            echo "[*] adding environment variable $ENV_KEY to runner"
            execute_runner_command "echo 'export $ENV_KEY=\"$ENV_VALUE\"' >> ~/.zprofile"
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[*] yolo_vm_run executed directly"
else
    echo "[*] yolo_vm_run sourced"
fi
