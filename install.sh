#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"
chmod +x ./*

for f in yolo_*.sh; do
	echo "[*] installing $f -> /usr/local/bin/$f"
	cp -f "$f" /usr/local/bin/
done
