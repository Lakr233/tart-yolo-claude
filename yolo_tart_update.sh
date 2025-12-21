#!/bin/zsh

set -euo pipefail

PREPARED_IMAGE_NAME="tart_yolo_base"
RUNNER_USERNAME="admin"
RUNNER_PASSWORD="admin"
RUNNER_IP=""

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
    sshpass -p "$RUNNER_PASSWORD" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -o ConnectTimeout=10 \
        -t \
        "$RUNNER_USERNAME@$RUNNER_IP" "source ~/.zprofile && $CMD"
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
        if execute_vm_command "echo hello" &> /dev/null; then
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
    echo "[*] updating brew and node tooling..."
    execute_vm_command "echo 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH' >> ~/.zprofile"
    execute_vm_command "touch ~/.zshrc && chmod +x ~/.zshrc"
    execute_vm_command "echo 'source ~/.zshrc' >> ~/.zprofile"
    execute_vm_command "brew update"
    execute_vm_command "brew upgrade"
    execute_vm_command "command -v npm >/dev/null 2>&1 && npm update -g || true"
    execute_vm_command "command -v pnpm >/dev/null 2>&1 && pnpm update -g || true"
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
