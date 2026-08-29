#!/bin/bash
# Builds dist/StayWake.app as a universal binary. Needs only the Swift
# toolchain from the Command Line Tools — no Xcode, no signing certificate.
#
# SwiftPM's own multi-arch mode (--arch arm64 --arch x86_64) requires XCBuild,
# which ships with Xcode, so instead we build each slice against its own
# triple and stitch them together with lipo.
set -euo pipefail

cd "$(dirname "$0")"

APP=dist/StayWake.app
CONTENTS="$APP/Contents"
DEPLOYMENT_TARGET=13.0
TRIPLES=(arm64-apple-macosx$DEPLOYMENT_TARGET x86_64-apple-macosx$DEPLOYMENT_TARGET)

slices=()
for triple in "${TRIPLES[@]}"; do
    echo "==> Compiling ${triple%%-*}"
    swift build -c release --triple "$triple"
    slices+=("$(swift build -c release --triple "$triple" --show-bin-path)/StayWake")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

lipo -create "${slices[@]}" -output "$CONTENTS/MacOS/StayWake"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp scripts/install-sudoers-rule.sh "$CONTENTS/Resources/install-sudoers-rule.sh"

# Ad-hoc signature. Enough for Gatekeeper to run a locally built app and to
# give the login-item registration a stable identity. Every slice must be
# signed after lipo, not before, or the signature will not validate.
echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo
echo "Built $APP  ($(lipo -archs "$CONTENTS/MacOS/StayWake"))"
echo "Run it with:      open $APP"
echo "Install it with:  cp -R $APP /Applications/"
