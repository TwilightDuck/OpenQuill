#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .verification
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
app="$PWD/.verification/TextFieldCheck.app"
mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 6 -parse-as-library -emit-module -emit-object -whole-module-optimization \
    -module-name FlowCore Sources/FlowCore/*.swift \
    -emit-module-path "$temporary/FlowCore.swiftmodule" -o "$temporary/FlowCore.o"
swiftc -swift-version 6 -parse-as-library -I "$temporary" \
    Sources/OpenQuill/MacIntegration.swift Sources/OpenQuill/FlowTheme.swift \
    scripts/TextFieldCheck.swift "$temporary/FlowCore.o" -o "$app/Contents/MacOS/OpenQuill"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Open Quill Text Field Check' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Open Quill Text Field Check' "$app/Contents/Info.plist"
./scripts/sign-local-app.sh "$app"
print "Built $app. Quit Open Quill before opening the check; reopen Open Quill afterward."
