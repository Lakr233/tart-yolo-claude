#!/bin/zsh

set -euo pipefail

if [[ "$0" == */* ]]; then
	SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
	SCRIPT_DIR="$(dirname "$(whence -p "$0")")"
fi

export TART_IMAGE="tart_yolo_base"
export RUNNER_IMAGE_NAME="yolo-claude-runner-${RANDOM}"
export MOUNT_PROJECT="${MOUNT_PROJECT:-$(pwd)}"
RUNNER_UPLOAD_EXCLUDES=(
	".claude/backups"
	".claude/debug"
	".claude/downloads"
	".claude/file-history"
	".claude/history.jsonl"
	".claude/ide"
	".claude/paste-cache"
	".claude/plans"
	".claude/projects"
	".claude/session-env"
	".claude/shell-snapshots"
	".claude/statsig"
	".claude/tasks"
	".claude/telemetry"
	".claude/todos"
	".claude/transcripts"
)

vm_bootstrap() {
	echo "[*] uploading claude configuration..."
	execute_runner_upload_batch "/Users/$RUNNER_USERNAME" \
		"${HOME}/.claude" \
		"${HOME}/.claude.json"

	execute_runner_export_envs "API_KEY"
}

export BOOT_COMMAND="cd ~/project && claude --dangerously-skip-permissions; exec zsh -l"

source "$SCRIPT_DIR/yolo_zsh.sh"
