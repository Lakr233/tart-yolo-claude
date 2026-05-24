# Tart YOLO

Run a disposable macOS Tart VM for AI coding tools.

## Requirements

- macOS host on Apple Silicon
- [Tart](https://github.com/cirruslabs/tart)
- `sshpass` from Homebrew

```bash
brew install hudochenkov/sshpass/sshpass
```

## Usage

From any project directory:

```bash
./yolo.sh
```

To install it globally:

```bash
sudo install -m 755 yolo.sh /usr/local/bin/yolo
```

Then run it from any project directory:

```bash
yolo
```

Prepare or refresh the base image manually:

```bash
yolo prepare
```

The script uses the current directory as the project mount, prepares `tart_yolo_base` when it is missing, clones a disposable runner VM, uploads tool configuration files, and opens a `zsh` shell at `~/project`.

Inside the VM, run the tool you need:

```bash
claude --dangerously-skip-permissions
codex --yolo
```

The runner VM is deleted when the shell exits.

## Configuration Upload

`yolo.sh` uploads an explicit whitelist of authentication and configuration files. The whitelist contains Claude and Codex files only.

Current whitelist:

```text
~/.claude.json
~/.claude/settings.json
~/.claude/mcp-needs-auth-cache.json
~/.codex/auth.json
~/.codex/config.toml
~/.codex/.codex-global-state.json
~/.codex/AGENTS.md
~/.codex/installation_id
~/.codex/models_cache.json
```

## Installed Tools

The base image setup installs:

- Homebrew packages: `git`, `curl`, `wget`, `htop`, `vim`, `nano`, `jq`, `yq`, `coreutils`, `tmux`, `python@3.13`, `swiftformat`, `xcbeautify`, `node`
- Claude Code
- Codex CLI
