#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"
chmod +x *.sh
chmod +x *.py
cp -f yolo_*.sh /usr/local/bin/
cp -f yolo_*.py /usr/local/bin/

PREPARED_IMAGE_NAME="tart_yolo_base"
tart stop "$PREPARED_IMAGE_NAME" || true
tart delete "$PREPARED_IMAGE_NAME" || true
./yolo_tart_prepare.sh
rm $(which yolo_tart_prepare.sh)

echo "[*] installation complete. You can now run 'yolo_claude.sh', 'yolo_codex.sh', or 'yolo_zsh.sh' from anywhere."
