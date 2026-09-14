#!/bin/sh
# Rebuild the overlay's keymap from your newest clean Bazecor backup, then restart it.
# Run after any change you save in Bazecor.
set -e
cd "$(dirname "$0")/decode"
python3 build_map.py >/dev/null
python3 export_layers.py
cd ..
pkill -x Lens 2>/dev/null || true
sleep 1
open -a "$PWD/Lens.app" --args --toggle f13 --serial
sleep 1
pgrep -x Lens >/dev/null && echo "overlay restarted" || echo "did not start; see lens.log"
