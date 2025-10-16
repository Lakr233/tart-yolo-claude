#!/bin/zsh

set -euo pipefail

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
        -t \
        "$RUNNER_USERNAME@$RUNNER_IP" "source ~/.zprofile && $CMD"
}
function execute_runner_upload() {
    local SRC="$1"
    local DEST="$2"
    sshpass -p "$RUNNER_PASSWORD" \
        scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
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

echo "[*] provisioning codex config.toml..."
CODEX_CONFIG_FILE=$(mktemp)
cat <<'EOF' > "$CODEX_CONFIG_FILE"
ask_for_approval = "never"
sandbox = "workspace-write"
skip_git_repo_check = true
EOF
execute_runner_command "mkdir -p ~/.config/codex"
execute_runner_upload "$CODEX_CONFIG_FILE" "/Users/$RUNNER_USERNAME/.config/codex/config.toml"
rm "$CODEX_CONFIG_FILE"

echo "[*] installing codex..."
execute_runner_command "brew install codex"

for ENV_KEY in $(printenv | cut -d= -f1); do
    if [[ "$ENV_KEY" == *"API_KEY"* ]]; then
        ENV_VALUE=$(printenv "$ENV_KEY")
        echo "[*] adding environment variable $ENV_KEY to runner"
        execute_runner_command "echo 'export $ENV_KEY=\"$ENV_VALUE\"' >> ~/.zprofile"
    fi
done

echo "[*] granting permission to codex..."
RUNNER_CODEX_PROJECT_CONFIG_CONTENT=(
    "[projects.\"$RUNNER_PROJECT_MOUNT\"]"
    "trust_level = \"trusted\""
    ""
    "approval_policy = never"
)
execute_runner_command "echo '' >> ~/.codex/config.toml"
for LINE in "${RUNNER_CODEX_PROJECT_CONFIG_CONTENT[@]}"; do
    execute_runner_command "echo '$LINE' >> ~/.codex/config.toml"
done

echo "[*] starting yolo-codex..."
RUNNER_CODEX_COMMAND=(
    "cd '$RUNNER_PROJECT_MOUNT'" # change to the mounted directory
    "codex"
)
RUNNER_CODEX_FULL_COMMAND=""
for CMD_PART in "${RUNNER_CODEX_COMMAND[@]}"; do
    RUNNER_CODEX_FULL_COMMAND="${RUNNER_CODEX_FULL_COMMAND} && ${CMD_PART}"
done
RUNNER_CODEX_FULL_COMMAND="${RUNNER_CODEX_FULL_COMMAND:4}" # remove leading ' && '
echo "[*] executing: $RUNNER_CODEX_FULL_COMMAND"
execute_runner_command "$RUNNER_CODEX_FULL_COMMAND"
