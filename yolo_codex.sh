#!/bin/zsh

set -euo pipefail

DROP_TO_SHELL=false
if [[ "$#" -gt 0 ]] && [[ "$1" == "--drop-to-shell" ]]; then
    DROP_TO_SHELL=true
fi

TART_IMAGE="ghcr.io/cirruslabs/macos-tahoe-xcode:latest"
RUNNER_IMAGE_NAME="yolo-codex-runner-${RANDOM}"
RUNNER_USERNAME="admin"
RUNNER_PASSWORD="admin"
RUNNER_IP=""
RUNNER_PROJECT_MOUNT="/Volumes/My Shared Files/project"

if ! command -v tart &> /dev/null
then
    echo "[-] tart could not be found"
    exit 1
fi

if ! command -v sshpass &> /dev/null
then
    echo "[-] sshpass could not be found"
    exit 1
fi

if echo $(tart list || true) | grep -q "$TART_IMAGE"; then
    echo "[*] runner image $TART_IMAGE already exists"
else
    echo "[*] runner image $TART_IMAGE does not exist, pulling..."
    tart pull "$TART_IMAGE"
fi

echo "[*] using runner image name: $RUNNER_IMAGE_NAME"
tart clone "$TART_IMAGE" "$RUNNER_IMAGE_NAME"

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
trap cleanup EXIT
trap cleanup INT
trap cleanup TERM
trap cleanup HUP
trap cleanup ERR

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
    sshpass -p "$RUNNER_PASSWORD" \
        scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -r "$SRC" \
        "$RUNNER_USERNAME@$RUNNER_IP:$DEST"
}

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
    echo "[*] installing codex..."
    execute_runner_command "brew install codex"

    for ENV_KEY in $(printenv | cut -d= -f1); do
        if [[ "$ENV_KEY" == *"API_KEY"* ]]; then
            ENV_VALUE=$(printenv "$ENV_KEY")
            echo "[*] adding environment variable $ENV_KEY to runner"
            execute_runner_command "echo 'export $ENV_KEY=\"$ENV_VALUE\"' >> ~/.zprofile"
        fi
    done

    echo "[*] starting yolo-codex..."
    RUNNER_CODEX_COMMAND="cd ~/projects && codex"
    echo "[*] executing: $RUNNER_CODEX_COMMAND"
    execute_runner_command "$RUNNER_CODEX_COMMAND"
fi
