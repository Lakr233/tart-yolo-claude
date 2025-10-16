#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"
cp -f yolo_*.sh /usr/local/bin/
