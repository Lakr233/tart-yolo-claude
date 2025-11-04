#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"
chmod +x *.sh
chmod +x *.py
cp -f yolo_*.sh /usr/local/bin/
cp -f yolo_*.py /usr/local/bin/

./yolo_tart_prepare.sh

echo "[*] installation complete. You can now run 'yolo_claude.sh', 'yolo_codex.sh', or 'yolo_zsh.sh' from anywhere."
