# Agent Requirements

These requirements are non-negotiable for this repository.

- For VM-related failures, test and verify inside the Tart VM. Host-machine results are not a substitute.
- When the task is to update `prepare`, run and validate `./yolo.sh prepare`; do not treat host CLI upgrades or host config edits as the fix.
- Do not modify user global config files as a substitute for fixing this repository or its VM preparation flow unless explicitly asked.
- Do not add fallback installation paths, workaround branches, or unrelated cleanup without explicit approval.
- For Codex and Claude Code installation changes, first check the official installation documentation, then implement the documented method exactly.
- Do not use Homebrew for Codex installation unless the user explicitly asks for the Homebrew path.
- If the base VM image already contains a system-managed Codex or Claude command, do not uninstall or delete it; install the desired user-managed command and make PATH prefer the user-managed location.
- After changing install logic, verify the actual command resolution and versions inside the VM with commands such as `which -a codex`, `codex --version`, `which -a claude`, and `claude --version`.
- If the user corrects direction, stop the current wrong process before continuing.
