#!/bin/bash
# Installs the sudoers rule that lets StayWake run pmset without a password.
# Must run as root:  sudo ./scripts/install-helper.sh [username]
set -euo pipefail

SUDOERS_FILE=/etc/sudoers.d/staywake
TARGET_USER="${1:-${SUDO_USER:-}}"

if [[ $EUID -ne 0 ]]; then
  echo "error: must run as root — try: sudo $0" >&2
  exit 1
fi
if [[ -z "$TARGET_USER" ]]; then
  echo "error: could not determine the user to grant; pass one as an argument" >&2
  exit 1
fi
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
  echo "error: no such user: $TARGET_USER" >&2
  exit 1
fi

TMP="$(mktemp /tmp/staywake-sudoers.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<EOF
# Installed by StayWake. Remove with: sudo rm $SUDOERS_FILE
#
# Grants exactly the four pmset invocations the app issues — nothing else.
# sudo matches the full argument list literally, so this cannot be used to run
# arbitrary pmset commands, and it grants no other binary.
Cmnd_Alias STAYWAKE_PMSET = /usr/bin/pmset -a disablesleep 1, \\
                            /usr/bin/pmset -a disablesleep 0, \\
                            /usr/bin/pmset -c sleep 0 disksleep 0 womp 1, \\
                            /usr/bin/pmset -c sleep 1 disksleep 10
$TARGET_USER ALL=(root) NOPASSWD: STAYWAKE_PMSET
EOF

# Never install a file that would break sudo for everyone.
visudo -c -f "$TMP" >/dev/null

install -m 0440 -o root -g wheel "$TMP" "$SUDOERS_FILE"
echo "installed $SUDOERS_FILE for user $TARGET_USER"
