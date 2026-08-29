#!/bin/bash
# Removes the StayWake sudoers rule.  sudo ./scripts/remove-sudoers-rule.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "error: must run as root — try: sudo $0" >&2
  exit 1
fi

rm -f /etc/sudoers.d/staywake
echo "removed /etc/sudoers.d/staywake"
