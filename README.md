# Tart YOLO Scripts

A collection of scripts to run AI assistants (Claude, Codex) in macOS VMs using Tart virtualization.

## Requirements

- macOS host
- [Tart](https://github.com/cirruslabs/tart) installed
- `sshpass` installed (`brew install hudochenkov/sshpass/sshpass`)
- API keys for respective services (e.g., OPENROUTER_API_KEY for usage tracking)

## Installation

Run the install script to make scripts executable and copy to `/usr/local/bin`:

```bash
./install.sh
```

## Usage

### Prepare Base Image

First, prepare the base macOS image:

```bash
./yolo_tart_prepare.sh
```

The base image setup installs CLI tools inside the VM via `vm_init.sh`:

- `npm i -g @anthropic-ai/claude-code@latest @openai/codex@latest @google/gemini-cli@latest opencode-ai`
- `uv tool install --python 3.13 kimi-cli` (requires `uv` first)

### Run Claude

Launch Claude in a macOS VM:

```bash
./yolo_claude.sh
```

### Run Codex

Launch Codex in a macOS VM:

```bash
./yolo_codex.sh
```

### Run Gemini

```bash
./yolo_gemini.sh
```

### Run OpenCode

```bash
./yolo_opencode.sh
```

### Run Kimi

```bash
./yolo_kimi.sh
```

### Interactive Zsh Session

Start an interactive zsh session in a macOS VM:

```bash
./yolo_zsh.sh
```

Options:
- `--boot-command "command"`: Execute a specific command instead of interactive shell
- `--mount-project /path/to/project`: Mount a project directory (defaults to current directory)

### Check API Usage

View OpenRouter API usage stats:

```bash
python3 yolo_usage.py
```

## Scripts Overview

- `install.sh`: Installs scripts to system path
- `yolo_claude.sh`: Runs Claude AI assistant in VM
- `yolo_codex.sh`: Runs Codex AI assistant in VM
- `yolo_tart_exec.sh`: Core VM execution utilities
- `yolo_tart_prepare.sh`: Prepares base macOS image
- `yolo_vm_init.sh`: Installs/updates tools inside the VM (pnpm/uv)
- `yolo_usage.py`: Checks API usage statistics
- `yolo_zsh.sh`: Generic VM launcher with zsh shell

## Tool Installation Notes

Inside the VM, setup installs these CLIs:

- `pnpm add -g @anthropic-ai/claude-code@latest @openai/codex@latest @google/gemini-cli@latest opencode-ai`
- `uv tool install --python 3.13 kimi-cli` (requires `uv` first)