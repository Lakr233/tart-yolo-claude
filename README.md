# Tart YOLO Scripts

A collection of scripts to run AI assistants in macOS VMs using Tart virtualization.

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

After installation, you should run `yolo_tart_prepare.sh` once to set up the base macOS image. Which will pull the latest macOS image with xcode pre-installed and execute initial setup.

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