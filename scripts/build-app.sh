#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product OpenQuill
binary_dir=$(swift build -c release --show-bin-path)
mkdir -p "$PWD/dist"
stage=$(mktemp -d "$PWD/dist/.package-XXXXXX")
destination="$PWD/dist/Open Quill.app"
cleanup() {
    if [[ ! -d "$destination" && -d "$stage/previous.app" ]]; then
        if ! mv "$stage/previous.app" "$destination"; then
            print -u2 "Previous app preserved at $stage/previous.app"
            return
        fi
    fi
    rm -rf "$stage"
}
trap cleanup EXIT
app="$stage/Open Quill.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/OpenQuill" "$app/Contents/MacOS/OpenQuill"
cp Resources/Info.plist "$app/Contents/Info.plist"
# SwiftPM locates resource bundles next to the executable when distributed as a .app.
for bundle in "$binary_dir"/*.bundle(N); do
    cp -R "$bundle" "$app/Contents/MacOS/"
done
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp LICENSE "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/Licenses"
for checkout in .build/checkouts/*(N/); do
    for license in "$checkout"/LICENSE*(N.) "$checkout"/NOTICE*(N.); do
        mkdir -p "$app/Contents/Resources/Licenses/${checkout:t}"
        cp "$license" "$app/Contents/Resources/Licenses/${checkout:t}/"
    done
done
cp -R .build/checkouts/FluidAudio/ThirdPartyLicenses "$app/Contents/Resources/Licenses/FluidAudioDependencies"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
./scripts/sign-local-app.sh "$app"
if [[ -d "$destination" ]]; then mv "$destination" "$stage/previous.app"; fi
mv "$app" "$destination"
print "Built $destination"
