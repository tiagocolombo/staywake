#!/bin/bash
# Builds dist/StayWake.app. Needs only the Swift toolchain from the Command
# Line Tools — no Xcode, no signing certificate.
set -euo pipefail

cd "$(dirname "$0")"

APP=dist/StayWake.app
CONTENTS="$APP/Contents"

echo "==> Compiling"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$(swift build -c release --show-bin-path)/StayWake" "$CONTENTS/MacOS/StayWake"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp scripts/install-helper.sh "$CONTENTS/Resources/install-helper.sh"

# Ad-hoc signature. Enough for Gatekeeper to run a locally built app and for
# the login-item registration to have a stable identity.
echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo
echo "Built $APP"
echo "Run it with:      open $APP"
echo "Install it with:  cp -R $APP /Applications/"
