#!/bin/zsh

set -euo pipefail

readonly SOURCE_IMAGE="ghcr.io/cirruslabs/macos-tahoe-xcode:latest"
readonly BASE_IMAGE="tart_yolo_base"
readonly RUNNER_IMAGE="yolo-runner-${RANDOM}"
readonly RUNNER_USERNAME="admin"
readonly RUNNER_PASSWORD="admin"
readonly RUNNER_HOME="/Users/admin"
readonly RUNNER_PROJECT_MOUNT="/Volumes/My Shared Files/project"
readonly RUNNER_DISPLAY="1366x768px"
readonly CLAUDE_KEYCHAIN_SERVICE="Claude Code-credentials"

SCRIPT_NAME="${0:t}"
PROJECT_DIR="$(pwd)"
RUNNER_IP=""
TART_RUN_PID=""
ACTIVE_IMAGE=""
CLEANUP_DONE=false
CLEANUP_IN_PROGRESS=false
EXIT_CODE=0

main() {
	setup_cleanup_traps
	check_dependencies

	case "$#" in
		0)
			run_runner
			;;
		1)
			run_command "$1"
			;;
		*)
			print_usage
			exit 2
			;;
	esac
}

run_command() {
	local command_name="$1"

	case "$command_name" in
		prepare)
			rebuild_base_image
			;;
		*)
			print_usage
			exit 2
			;;
	esac
}

run_runner() {
	ensure_base_image
	prepare_runner_image
	start_runner
	link_project_directory
	upload_tool_configuration
	open_runner_shell
}

print_usage() {
	echo "Usage: $SCRIPT_NAME [prepare]" >&2
}

check_dependencies() {
	require_command tart
	require_command sshpass
	require_command tar
	require_command dscl
	require_command security
}

require_command() {
	local command_name="$1"

	if command -v "$command_name" >/dev/null 2>&1; then
		return
	fi

	echo "[-] required command missing: $command_name" >&2
	exit 1
}

ensure_base_image() {
	if local_tart_image_exists "$BASE_IMAGE"; then
		return
	fi

	create_base_image
}

rebuild_base_image() {
	delete_base_image
	create_base_image
}

delete_base_image() {
	if ! local_tart_image_exists "$BASE_IMAGE"; then
		return
	fi

	echo "[*] deleting existing base image: $BASE_IMAGE"
	tart stop "$BASE_IMAGE" >/dev/null 2>&1 || true
	tart delete "$BASE_IMAGE"
}

create_base_image() {
	echo "[*] preparing base image: $BASE_IMAGE"
	pull_source_image
	tart clone "$SOURCE_IMAGE" "$BASE_IMAGE"
	tart set "$BASE_IMAGE" --display "$RUNNER_DISPLAY" --no-display-refit
	boot_base_image_for_setup
	install_runner_tools
	stop_base_image
	echo "[*] base image ready: $BASE_IMAGE"
}

pull_source_image() {
	if tart_image_exists "$SOURCE_IMAGE"; then
		return
	fi

	echo "[*] pulling source image: $SOURCE_IMAGE"
	tart pull "$SOURCE_IMAGE"
}

local_tart_image_exists() {
	local image_name="$1"

	tart list 2>/dev/null | awk 'NR > 1 && $1 == "local" { print $2 }' | grep -Fxq "$image_name"
}

tart_image_exists() {
	local image_name="$1"

	tart list 2>/dev/null | awk 'NR > 1 { print $2 }' | grep -Fxq "$image_name"
}

boot_base_image_for_setup() {
	echo "[*] starting base image for setup..."
	start_tart_run "$BASE_IMAGE" --no-audio --no-clipboard

	wait_for_runner_ip "$BASE_IMAGE"
	wait_for_ssh
}

start_tart_run() {
	local image_name="$1"
	shift

	zsh -c 'trap "" INT; exec "$@"' tart-run tart run "$image_name" "$@" &
	TART_RUN_PID=$!
	ACTIVE_IMAGE="$image_name"
}

install_runner_tools() {
	echo "[*] installing tools in base image..."
	runner_init_script | sshpass -p "$RUNNER_PASSWORD" \
		ssh "${SSH_OPTIONS[@]}" \
		"$RUNNER_USERNAME@$RUNNER_IP" \
		"zsh -lc 'cat > ~/yolo_bootstrap.sh && chmod +x ~/yolo_bootstrap.sh && ~/yolo_bootstrap.sh'"
}

stop_base_image() {
	echo "[*] stopping base image..."
	tart stop "$BASE_IMAGE"
	TART_RUN_PID=""
	ACTIVE_IMAGE=""
	RUNNER_IP=""
}

prepare_runner_image() {
	echo "[*] cloning runner image: $RUNNER_IMAGE"
	tart clone "$BASE_IMAGE" "$RUNNER_IMAGE"
	tart set "$RUNNER_IMAGE" --display "$RUNNER_DISPLAY" --no-display-refit
	start_delete_guard
}

start_delete_guard() {
	local parent_pid="$$"
	local tart_bin
	tart_bin="$(command -v tart)"

	nohup zsh -c '
		trap "" INT TERM HUP

		runner_image="$1"
		parent_pid="$2"
		tart_bin="$3"

		while kill -0 "$parent_pid" 2>/dev/null; do
			sleep 1
		done

		"$tart_bin" stop "$runner_image" >/dev/null 2>&1 || true

		attempt=1
		while [ "$attempt" -le 15 ]; do
			"$tart_bin" delete "$runner_image" >/dev/null 2>&1 && exit 0
			"$tart_bin" list 2>/dev/null | awk "NR > 1 { print \$2 }" | grep -Fxq "$runner_image" || exit 0
			sleep 2
			attempt=$((attempt + 1))
		done
	' yolo-delete-guard "$RUNNER_IMAGE" "$parent_pid" "$tart_bin" >/dev/null 2>&1 &
}

setup_cleanup_traps() {
	trap 'handle_interrupt' INT TERM HUP
}

handle_interrupt() {
	echo "[*] interrupt received; cleaning up..."
	EXIT_CODE=130
	trap '' INT TERM HUP
	cleanup || true
	exit "$EXIT_CODE"
}

TRAPEXIT() {
	local exit_code=$?

	if [ "$EXIT_CODE" -ne 0 ]; then
		exit_code="$EXIT_CODE"
	fi

	trap '' INT TERM HUP
	cleanup || true
	return "$exit_code"
}

cleanup() {
	if [ "$CLEANUP_DONE" = true ]; then
		return
	fi

	if [ "$CLEANUP_IN_PROGRESS" = true ]; then
		return
	fi

	CLEANUP_IN_PROGRESS=true
	stop_active_vm
	delete_runner_image
	CLEANUP_DONE=true
	CLEANUP_IN_PROGRESS=false
}

stop_active_vm() {
	if [ -n "$TART_RUN_PID" ] && kill -0 "$TART_RUN_PID" 2>/dev/null; then
		echo "[*] stopping tart run process: $TART_RUN_PID"
		kill "$TART_RUN_PID" 2>/dev/null || true
		wait "$TART_RUN_PID" 2>/dev/null || true
	fi

	TART_RUN_PID=""

	if [ -n "$ACTIVE_IMAGE" ]; then
		tart stop "$ACTIVE_IMAGE" >/dev/null 2>&1 || true
		ACTIVE_IMAGE=""
	fi
}

delete_runner_image() {
	local attempt=1
	local max_attempts=15

	while [ "$attempt" -le "$max_attempts" ]; do
		tart stop "$RUNNER_IMAGE" >/dev/null 2>&1 || true

		if tart delete "$RUNNER_IMAGE" >/dev/null 2>&1; then
			echo "[*] deleted runner image: $RUNNER_IMAGE"
			return
		fi

		if ! local_tart_image_exists "$RUNNER_IMAGE"; then
			return
		fi

		echo "[*] runner image busy; retrying delete ($attempt/$max_attempts)..."
		sleep 2
		attempt=$((attempt + 1))
	done

	echo "[-] failed to delete runner image: $RUNNER_IMAGE" >&2
	return 1
}

start_runner() {
	echo "[*] starting runner image, mounting $PROJECT_DIR..."
	start_tart_run "$RUNNER_IMAGE" \
		--dir=project:"$PROJECT_DIR" \
		--no-audio \
		--no-clipboard

	wait_for_runner_ip "$RUNNER_IMAGE"
	wait_for_ssh
}

wait_for_runner_ip() {
	local image_name="$1"
	local attempts=0

	while [ -z "$RUNNER_IP" ] && [ "$attempts" -lt 30 ]; do
		sleep 2
		attempts=$((attempts + 1))
		RUNNER_IP="$(tart ip "$image_name" 2>/dev/null || true)"
	done

	if [ -n "$RUNNER_IP" ]; then
		echo "[*] runner ip address: $RUNNER_IP"
		return
	fi

	echo "[-] failed to get VM ip address: $image_name" >&2
	exit 1
}

wait_for_ssh() {
	local attempts=0

	while [ "$attempts" -lt 30 ]; do
		if execute_runner_command "echo hello" >/dev/null 2>&1; then
			echo "[*] ssh is ready"
			return
		fi

		sleep 2
		attempts=$((attempts + 1))
	done

	echo "[-] failed to establish ssh connectivity: $RUNNER_IP" >&2
	exit 1
}

link_project_directory() {
	execute_runner_command "ln -sfn '$RUNNER_PROJECT_MOUNT' ~/project"
}

upload_tool_configuration() {
	local user_home
	user_home="$(current_user_home)"

	echo "[*] uploading tool configuration..."
	upload_existing_paths "$user_home" "$RUNNER_HOME" \
		".claude.json" \
		".claude/settings.json" \
		".claude/mcp-needs-auth-cache.json" \
		".codex/auth.json" \
		".codex/config.toml" \
		".codex/.codex-global-state.json" \
		".codex/AGENTS.md" \
		".codex/installation_id" \
		".codex/models_cache.json"

	upload_claude_keychain_credentials
}

upload_claude_keychain_credentials() {
	local source_account
	local payload_path
	local remote_payload_path

	source_account="$(id -un)"
	payload_path="$(mktemp)"
	remote_payload_path="/tmp/yolo_claude_keychain_credentials_$$.json"

	if ! security find-generic-password -a "$source_account" -w -s "$CLAUDE_KEYCHAIN_SERVICE" >"$payload_path" 2>/dev/null; then
		rm -f "$payload_path"
		echo "[*] no Claude Code keychain credentials found"
		return
	fi

	echo "[*] uploading Claude Code keychain credentials..."
	chmod 600 "$payload_path"

	{
		sshpass -p "$RUNNER_PASSWORD" \
			scp "${SCP_OPTIONS[@]}" \
			"$payload_path" \
			"$RUNNER_USERNAME@$RUNNER_IP:$remote_payload_path"

		sshpass -p "$RUNNER_PASSWORD" \
			ssh "${SSH_OPTIONS[@]}" \
			"$RUNNER_USERNAME@$RUNNER_IP" \
			"zsh -s -- '$remote_payload_path' '$CLAUDE_KEYCHAIN_SERVICE' '$RUNNER_PASSWORD'" <<'IMPORT_CLAUDE_KEYCHAIN'
set -euo pipefail

remote_payload_path="$1"
service="$2"
runner_password="$3"
account="$(id -un)"
payload="$(cat "$remote_payload_path")"
rm -f "$remote_payload_path"

if [ -z "$payload" ]; then
	echo "[-] Claude Code keychain credential payload is empty" >&2
	exit 1
fi

security unlock-keychain -p "$runner_password" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
security add-generic-password -U -a "$account" -s "$service" -w "$payload" >/dev/null

if [ -z "$(security find-generic-password -a "$account" -w -s "$service")" ]; then
	echo "[-] failed to store Claude Code keychain credential payload" >&2
	exit 1
fi
IMPORT_CLAUDE_KEYCHAIN
	} always {
		rm -f "$payload_path"
		execute_runner_command "rm -f '$remote_payload_path'" >/dev/null 2>&1 || true
	}
}

current_user_home() {
	local user_name
	local home_dir

	user_name="$(id -un)"
	home_dir="$(dscl . -read "/Users/$user_name" NFSHomeDirectory | awk '{ print $2 }')"

	if [ -d "$home_dir" ]; then
		echo "$home_dir"
		return
	fi

	echo "[-] failed to resolve current user home directory" >&2
	exit 1
}

upload_existing_paths() {
	local source_home="$1"
	local destination_home="$2"
	shift 2

	local relative_paths=()
	local relative_path

	for relative_path in "$@"; do
		if [ -e "$source_home/$relative_path" ]; then
			relative_paths+=("$relative_path")
			echo "[*] including $relative_path"
		fi
	done

	if [ "${#relative_paths[@]}" -eq 0 ]; then
		echo "[*] no tool configuration files found"
		return
	fi

	upload_tar_archive "$source_home" "$destination_home" "${relative_paths[@]}"
}

upload_tar_archive() {
	local source_home="$1"
	local destination_home="$2"
	shift 2

	local archive_path="/tmp/yolo_upload_$$.tar.gz"

	tar -czf "$archive_path" -C "$source_home" "$@"
	sshpass -p "$RUNNER_PASSWORD" \
		scp "${SCP_OPTIONS[@]}" \
		"$archive_path" \
		"$RUNNER_USERNAME@$RUNNER_IP:/tmp/yolo_upload.tar.gz"
	rm -f "$archive_path"

	execute_runner_command "tar -xzf /tmp/yolo_upload.tar.gz -C '$destination_home' && rm -f /tmp/yolo_upload.tar.gz"
}

open_runner_shell() {
	echo "[*] opening runner shell..."
	execute_runner_command "security unlock-keychain -p '$RUNNER_PASSWORD' ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true; cd ~/project && exec zsh -l"
	trap - EXIT INT TERM HUP
	cleanup
}

execute_runner_command() {
	local command_text="$1"

	sshpass -p "$RUNNER_PASSWORD" \
		ssh -t "${SSH_OPTIONS[@]}" \
		"$RUNNER_USERNAME@$RUNNER_IP" \
		"[[ -f ~/.zshenv ]] && source ~/.zshenv; $command_text"
}

typeset -ra SSH_OPTIONS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o PreferredAuthentications=password
	-o ConnectTimeout=30
)

typeset -ra SCP_OPTIONS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o PreferredAuthentications=password
	-o ConnectTimeout=30
)

runner_init_script() {
	cat <<'RUNNER_INIT'
#!/bin/zsh

set -euo pipefail

ensure_line_in_file() {
	local line="$1"
	local file="$2"

	mkdir -p "$(dirname "$file")" 2>/dev/null || true
	touch "$file"

	if grep -qxF "$line" "$file"; then
		return
	fi

	echo "$line" >>"$file"
}

echo "[*] yolo VM init: starting..."

ensure_line_in_file 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' "$HOME/.zshenv"
ensure_line_in_file 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.zshenv"
ensure_line_in_file 'export PNPM_HOME=$HOME/Library/pnpm' "$HOME/.zshenv"
ensure_line_in_file 'export PATH=$PNPM_HOME:$PATH' "$HOME/.zshenv"
ensure_line_in_file 'export PATH=$HOME/.local/bin:$PATH' "$HOME/.zprofile"

source "$HOME/.zshenv"

export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_UPGRADE=1

echo "[*] installing base development tools..."
brew update
brew install --force --overwrite \
	git curl wget htop vim nano jq yq coreutils tmux \
	python@3.13 \
	swiftformat xcbeautify \
	node

if command -v node >/dev/null 2>&1; then
	echo "[*] node is ready"
else
	echo "[-] node missing after brew install" >&2
	exit 1
fi

if command -v tmux >/dev/null 2>&1; then
	echo "[*] tmux is ready"
else
	echo "[-] tmux missing after brew install" >&2
	exit 1
fi

PNPM_HOME="$HOME/Library/pnpm"
mkdir -p "$PNPM_HOME"
export PNPM_HOME
export PATH="$PNPM_HOME:$PATH"

if command -v corepack >/dev/null 2>&1; then
	echo "[*] enabling corepack/pnpm..."
	corepack enable || true
	corepack prepare pnpm@latest --activate || true
fi

if command -v pnpm >/dev/null 2>&1; then
	echo "[*] pnpm is ready"
elif command -v npm >/dev/null 2>&1; then
	echo "[*] installing pnpm via npm..."
	npm i -g pnpm
else
	echo "[-] npm missing after node install" >&2
	exit 1
fi

PNPM_GLOBAL_DIR="$HOME/Library/pnpm/global"
mkdir -p "$PNPM_GLOBAL_DIR"

echo "[*] configuring pnpm global dirs..."
pnpm config set global-bin-dir "$PNPM_HOME"
pnpm config set global-dir "$PNPM_GLOBAL_DIR"

PNPM_GLOBAL_BIN_DIR="$(pnpm config get global-bin-dir)"
case ":$PATH:" in
	*":$PNPM_GLOBAL_BIN_DIR:"*) ;;
	*)
		echo "[-] pnpm global bin dir missing from PATH: $PNPM_GLOBAL_BIN_DIR" >&2
		exit 1
		;;
esac

echo "[*] installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
claude --version

echo "[*] installing Codex CLI..."
CODEX_TMP_DIR="$(mktemp -d)"
curl -fsSL https://github.com/openai/codex/releases/latest/download/codex-aarch64-apple-darwin.tar.gz -o "$CODEX_TMP_DIR/codex.tar.gz"
tar -xzf "$CODEX_TMP_DIR/codex.tar.gz" -C "$CODEX_TMP_DIR"
install -m 755 "$CODEX_TMP_DIR/codex-aarch64-apple-darwin" "$HOME/.local/bin/codex"
rm -rf "$CODEX_TMP_DIR"
codex --version

echo "[*] cleaning up..."
brew cleanup || true

echo "[*] yolo VM init completed"
RUNNER_INIT
}

main "$@"
