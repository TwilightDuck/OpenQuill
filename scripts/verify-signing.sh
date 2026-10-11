#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/dist/Open Quill.app"
[[ -d "$app" ]] || { print -u2 "Build the app first."; exit 1; }
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
cp -R "$app" "$temporary/original.app"
cp -R "$app" "$temporary/rebuilt.app"
requirement=$(codesign --display --requirements - "$temporary/original.app" 2>&1 | sed -n -E 's/^(# )?designated => //p')
[[ -n "$requirement" ]] || { print -u2 "The app has no identity requirement."; exit 1; }
original_hash=$(codesign --display --verbose=4 "$temporary/original.app" 2>&1 | rg '^CDHash=')
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$temporary/rebuilt.app/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build_number + 1))" "$temporary/rebuilt.app/Contents/Info.plist"
./scripts/sign-local-app.sh "$temporary/rebuilt.app"
rebuilt_hash=$(codesign --display --verbose=4 "$temporary/rebuilt.app" 2>&1 | rg '^CDHash=')
[[ "$original_hash" != "$rebuilt_hash" ]] || { print -u2 "Verification did not create a different build."; exit 1; }
codesign --verify --deep --strict --test-requirement "=$requirement" "$temporary/rebuilt.app"

# A valid ad-hoc signature must not impersonate the certificate-signed app.
cp -R "$temporary/rebuilt.app" "$temporary/different-signer.app"
codesign --force --sign - --identifier be.nick.wisperflow "$temporary/different-signer.app"
codesign --verify --deep --strict "$temporary/different-signer.app"
if codesign --verify --test-requirement "=$requirement" "$temporary/different-signer.app" > "$temporary/rejection.log" 2>&1; then
    print -u2 "A different signer incorrectly satisfied the app identity."
    exit 1
fi
print 'PASS: different builds retain the app identity; a different signer is rejected.'
print 'This verifies signing continuity. OS permission retention requires a real grant and relaunch.'
