#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"

clear
echo "RetroRelay Rumor2MacProbe"
echo "This is a read-only Mac-native LG USB/BREW probe."
echo

python3 "$SCRIPT_DIR/rumor2_mac_probe.py" --deep

echo
echo "Press Return to close this window."
read _
