#!/bin/bash
# Certificate-free local/CI distribution. No notarization or Apple credentials.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
DERIVED_DATA="${FLUIDVOICE_DERIVED_DATA_PATH:-$PROJECT_DIR/DerivedData}"
OUTPUT_DIR="${FLUIDVOICE_ARTIFACT_DIR:-$PROJECT_DIR/builds}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FluidVoice.app"
ARCH="$(uname -m)"

python3 Tests/check_network_policy.py
xcodebuild -project Fluid.xcodeproj -scheme Fluid -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    ONLY_ACTIVE_ARCH=YES ARCHS="$ARCH" build

test -d "$APP_PATH"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/fluidvoice-adhoc.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$OUTPUT_DIR"
export APP_PATH STAGING
python3 - <<'PY'
import os, pathlib, plistlib, shutil
app = pathlib.Path(os.environ['APP_PATH'])
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as file:
    info = plistlib.load(file)
info['CFBundleIdentifier'] = 'com.kwsp.FluidVoice'
with info_path.open('wb') as file:
    plistlib.dump(info, file)
framework = app / 'Contents/Frameworks/CTranscribe.framework'
assert (framework / 'Versions/A/CTranscribe').is_file()
assert (framework / 'Versions/A/Resources').is_dir()
# Xcode flattens this downloaded framework's version links; restore before signing.
for relative, target in [('Versions/Current', 'A'), ('CTranscribe', 'Versions/Current/CTranscribe'), ('Resources', 'Versions/Current/Resources')]:
    path = framework / relative
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    path.symlink_to(target)
with open('Fluid.entitlements', 'rb') as file:
    entitlements = plistlib.load(file)
# The unsigned build doesn't expand Xcode's Hardened Runtime Audio Input capability.
entitlements['com.apple.security.device.audio-input'] = True
with open(pathlib.Path(os.environ['STAGING']) / 'app.entitlements', 'wb') as file:
    plistlib.dump(entitlements, file)
PY

# Sign embedded code first, then seal the outer app. Do not use --deep to sign.
while IFS= read -r -d '' framework; do
    codesign --force --sign - --timestamp=none "$framework"
done < <(find "$APP_PATH/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
codesign --force --sign - --timestamp=none --options runtime \
    --entitlements "$STAGING/app.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements - --xml "$APP_PATH" > "$STAGING/signed.entitlements" 2>/dev/null
python3 - <<'PY'
import os, pathlib, plistlib
with open(pathlib.Path(os.environ['STAGING']) / 'signed.entitlements', 'rb') as file:
    assert plistlib.load(file).get('com.apple.security.device.audio-input') is True
PY

test "$(lipo -archs "$APP_PATH/Contents/MacOS/FluidVoice")" = "$ARCH"
while IFS= read -r dependency; do
    test -e "$APP_PATH/Contents/Frameworks/${dependency#@rpath/}" || {
        echo "Missing embedded dependency: $dependency" >&2
        exit 1
    }
done < <(otool -L "$APP_PATH/Contents/MacOS/FluidVoice" | awk '$1 ~ /^@rpath\// { print $1 }')
ZIP_PATH="$OUTPUT_DIR/FluidVoice-Local-$ARCH.app.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
# Verify the distributable, including framework symlinks, after extraction.
ditto -x -k "$ZIP_PATH" "$STAGING/verify"
codesign --verify --deep --strict --verbose=2 "$STAGING/verify/FluidVoice.app"
(cd "$OUTPUT_DIR" && shasum -a 256 "FluidVoice-Local-$ARCH.app.zip" > SHA256SUMS)
{
    echo "Source commit: $(git rev-parse HEAD)"
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree: modified"
    else
        echo "Working tree: clean"
    fi
    echo "Architecture: $ARCH"
    echo "Bundle ID: com.kwsp.FluidVoice"
    echo "Signing: ad-hoc (no certificate, not notarized)"
    xcodebuild -version
} > "$OUTPUT_DIR/build-info.txt"
cat > "$OUTPUT_DIR/README.txt" <<'EOF'
FluidVoice local-data fork — ad-hoc signed build

Extract the app ZIP and move FluidVoice.app into Applications.
This app has no Apple Developer ID certificate and is not notarized.
macOS may require Privacy & Security > Open Anyway after the first launch attempt.
Grant microphone/Accessibility permissions as prompted. Ad-hoc rebuilds may need
permissions granted again. The fork has its own bundle ID: com.kwsp.FluidVoice.

Telemetry and feedback uploads are removed; AI requests are loopback-only.
STT downloads remain enabled. Command subprocess networking and upstream updater
traffic are still deferred; see PRIVACY_CHECKLIST.md in the source repository.
EOF
echo "App: $APP_PATH"
echo "Downloadable ZIP: $ZIP_PATH"
