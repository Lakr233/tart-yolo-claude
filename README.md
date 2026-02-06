# Tart YOLO Scripts

A collection of scripts to run AI coding assistants in sandboxed macOS VMs using [Tart](https://github.com/cirruslabs/tart) virtualization.

## Requirements

- macOS host (Apple Silicon)
- [Tart](https://github.com/cirruslabs/tart) installed
- `sshpass` installed (`brew install hudochenkov/sshpass/sshpass`)
- API keys for respective services (e.g., `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`)

## Installation

Run the install script to copy all scripts to `/usr/local/bin`:

```bash
./install.sh
```

Then run `yolo_tart_prepare.sh` once to build the base macOS image. This pulls the latest macOS Tahoe image with Xcode pre-installed and runs initial tool setup.

## Usage

From any project directory:

```bash
yolo_claude.sh    # Claude Code (--dangerously-skip-permissions)
yolo_codex.sh     # OpenAI Codex (--yolo)
yolo_gemini.sh    # Google Gemini CLI (--yolo)
yolo_kimi.sh      # Kimi CLI (--yolo)
yolo_opencode.sh  # OpenCode (OPENCODE_YOLO=true)
yolo_zsh.sh       # Plain zsh shell in VM
```

Each script clones an ephemeral VM from the base image, mounts your current directory at `~/project`, uploads configuration files and API keys, then launches the tool. When the tool exits (including Ctrl+C), you drop into an interactive zsh shell inside the VM instead of tearing it down — exit the shell to clean up.

Environment variables matching `*API_KEY*` are automatically forwarded to the VM.

## Scripts Overview

- `install.sh` — Installs scripts to `/usr/local/bin`
- `yolo_tart_prepare.sh` — One-time base image preparation
- `yolo_tart_exec.sh` — Shared VM lifecycle utilities (start, upload, cleanup)
- `yolo_vm_init.sh` — Tool installation inside the VM
- `yolo_zsh.sh` — Generic VM launcher
- `yolo_claude.sh` — Claude Code launcher
- `yolo_codex.sh` — Codex launcher
- `yolo_gemini.sh` — Gemini CLI launcher
- `yolo_kimi.sh` — Kimi CLI launcher
- `yolo_opencode.sh` — OpenCode launcher
- `yolo_usage.py` — API usage statistics checker

## How Bootstrap Works

Configuration files (e.g., `~/.claude`, `~/.claude.json`) are tarred locally, transferred as a single archive via SCP, and extracted on the VM. API keys are batched into one SSH call. This minimizes SSH connection overhead during boot.

## Pre-installed Tools (via `yolo_vm_init.sh`)

Homebrew packages: git, curl, wget, htop, vim, nano, jq, yq, coreutils, python@3.13, node, uv, swiftformat, xcbeautify

AI CLIs:
- **Claude Code** — native installer (`claude.ai/install.sh`)
- **OpenCode** — native installer (`opencode.ai/install`)
- **Codex, Gemini CLI** — via pnpm (`@openai/codex`, `@google/gemini-cli`)
- **Kimi CLI** — via uv (`kimi-cli`, Python 3.13)
- **ralph-claude-code** — cloned from GitHub
