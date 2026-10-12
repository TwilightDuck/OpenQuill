#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/dist/Open Quill.app"
[[ -d "$app" ]] || { print -u2 'Run ./scripts/build-app.sh first.'; exit 1; }
codesign --verify --deep --strict "$app"
[[ $(lipo -archs "$app/Contents/MacOS/OpenQuill") == arm64 ]] || { print -u2 'This package requires an arm64 build.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
name="Open-Quill-$version-macOS-arm64"
mkdir -p dist/releases
destination="$PWD/dist/releases/v$version"
[[ ! -e "$destination" ]] || { print -u2 "Release artifacts already exist at $destination; preserve published artifacts."; exit 1; }
stage=$(mktemp -d "$PWD/dist/.release-XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/Applications" "$stage/image" "$stage/resources" "$stage/output"
# Copy the app alone, without host provenance or development-directory contents.
ditto --noextattr --norsrc "$app" "$stage/root/Applications/Open Quill.app"
ditto --noextattr --norsrc "$app" "$stage/image/Open Quill.app"
ln -s /Applications "$stage/image/Applications"
cat > "$stage/image/Read Me.txt" <<EOF
Open Quill $version — Preview

Drag Open Quill to Applications, then open it from Applications.
Requires an Apple silicon Mac running macOS 14 or later.

This preview is locally signed, but is not Apple-notarized. The installer
is unsigned. macOS may block opening these downloads and require explicit
approval. Apple's guidance: https://support.apple.com/en-us/102445

Setup guides you through permissions and a free speech-model download.
Dictation then runs locally. No account, subscription or API key is needed.
Optional AI cleanup requires macOS 26+ and Apple Intelligence.

App and model credits are included inside the app's Resources folder.
EOF
cat > "$stage/resources/Welcome.html" <<'HTML'
<!doctype html><html><body>
<h1>Open Quill</h1>
<p>Free, local dictation for your Mac.</p>
<p>This installer places Open Quill in Applications. Requires Apple silicon and macOS 14 or later.</p>
<p><strong>Preview:</strong> the installer is unsigned and the app is not Apple-notarized. macOS may require explicit approval to open it.</p>
<p>After installation, setup guides you through microphone and Accessibility permissions and a free speech-model download. Models and personal data stay outside the app, so app updates preserve them.</p>
<p>Quit Open Quill before installing an update.</p>
</body></html>
HTML
cat > "$stage/resources/Conclusion.html" <<'HTML'
<!doctype html><html><body>
<h1>Ready to set up Open Quill</h1>
<p>Open Open Quill from Applications. Complete setup, select a text field, then middle-click or press Option-Space to dictate.</p>
<p>This preview is not Apple-notarized. If macOS blocks it, review <a href="https://support.apple.com/en-us/102445">Apple's app-opening guidance</a>.</p>
</body></html>
HTML
pkgbuild --analyze --root "$stage/root" "$stage/components.plist"
python3 - "$stage" <<'PY'
from pathlib import Path
import plistlib, sys
stage = Path(sys.argv[1])
file = stage / 'components.plist'
components = plistlib.loads(file.read_bytes())
def configure(items):
    for item in items:
        item.update(BundleIsRelocatable=False, BundleIsVersionChecked=True,
                    BundleHasStrictIdentifier=True, BundleOverwriteAction='upgrade')
        configure(item.get('ChildBundles', []))
configure(components)
file.write_bytes(plistlib.dumps(components))
(stage / 'requirements.plist').write_bytes(plistlib.dumps({'os': ['14.0'], 'arch': ['arm64'], 'home': False}))
PY
pkgbuild --root "$stage/root" --component-plist "$stage/components.plist" \
    --identifier be.nick.openquill.installer --version "$version" --install-location / \
    "$stage/OpenQuill-component.pkg"
productbuild --synthesize --product "$stage/requirements.plist" \
    --package "$stage/OpenQuill-component.pkg" "$stage/Distribution.xml"
python3 - "$stage/Distribution.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
file = sys.argv[1]
tree = ET.parse(file); root = tree.getroot()
ET.SubElement(root, 'title').text = 'Open Quill'
root.find('options').set('customize', 'never')
ET.SubElement(root, 'domains', enable_anywhere='false', enable_currentUserHome='false', enable_localSystem='true')
ET.SubElement(root, 'welcome', file='Welcome.html', **{'mime-type': 'text/html'})
ET.SubElement(root, 'conclusion', file='Conclusion.html', **{'mime-type': 'text/html'})
tree.write(file, encoding='utf-8', xml_declaration=True)
PY
productbuild --distribution "$stage/Distribution.xml" --resources "$stage/resources" \
    --package-path "$stage" "$stage/output/$name.pkg"
hdiutil create -quiet -srcfolder "$stage/image" -volname "Open Quill $version" \
    -format UDZO "$stage/output/$name.dmg"
hdiutil verify "$stage/output/$name.dmg" >/dev/null

# Check the real installer payload before exposing download artifacts.
pkgutil --expand-full "$stage/output/$name.pkg" "$stage/expanded"
payload="$stage/expanded/OpenQuill-component.pkg/Payload/Applications/Open Quill.app"
codesign --verify --deep --strict "$payload"
diff -qr "$stage/root/Applications/Open Quill.app" "$payload" >/dev/null
[[ -f "$payload/Contents/Resources/LICENSE" && -f "$payload/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
(
    cd "$stage/output"
    shasum -a 256 "$name.pkg" "$name.dmg" > SHA256SUMS.txt
)
mv "$stage/output" "$destination"
print "Prepared non-notarized preview artifacts in $destination"
