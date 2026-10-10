#!/bin/zsh
set -euo pipefail
umask 077
app=${1:?Pass the app bundle to sign}
signing_dir="$HOME/Library/Application Support/WisperFlowBuildSigning"
keychain="$signing_dir/local-signing.keychain-db"
certificate="$signing_dir/certificate.pem"
password_file="$signing_dir/keychain-password"
mkdir -p "$signing_dir"
chmod 700 "$signing_dir"
temporary=$(mktemp -d "$signing_dir/.setup-XXXXXX")
restore_search_list=false
cleanup() {
    if $restore_search_list; then security list-keychains -d user -s "${previous_keychains[@]}"; fi
    security lock-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$temporary"
}
trap cleanup EXIT

if [[ ! -f "$certificate" ]]; then
    [[ ! -f "$keychain" ]] || { print -u2 "Incomplete local signing setup in $signing_dir"; exit 1; }
    /usr/bin/openssl rand -hex 32 > "$password_file"
    cat > "$temporary/certificate.conf" <<'EOF'
[req]
distinguished_name = identity
x509_extensions = signing
prompt = no
[identity]
CN = Open Whisper Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
        -config "$temporary/certificate.conf" -keyout "$temporary/key.pem" \
        -out "$temporary/certificate.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$temporary/key.pem" \
        -in "$temporary/certificate.pem" -out "$temporary/identity.p12" \
        -passout "file:$password_file"
    # Creating a keychain adds it to the search list; immediately restore that list.
    previous_keychains=()
    while read -r entry; do
        entry=${entry#\"}; entry=${entry%\"}
        previous_keychains+=("$entry")
    done < <(security list-keychains -d user)
    signing_password=$(<"$password_file")
    restore_search_list=true
    security create-keychain -p "$signing_password" "$keychain"
    security list-keychains -d user -s "${previous_keychains[@]}"
    restore_search_list=false
    security import "$temporary/identity.p12" -k "$keychain" -P "$signing_password" \
        -x -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S codesign: -s -k "$signing_password" "$keychain" >/dev/null
    cp "$temporary/certificate.pem" "$certificate"
fi

[[ -f "$keychain" && -f "$password_file" ]] || { print -u2 "Local signing identity is incomplete."; exit 1; }
signing_password=$(<"$password_file")
security unlock-keychain -p "$signing_password" "$keychain"
fingerprint=$(/usr/bin/openssl x509 -in "$certificate" -noout -sha1 -fingerprint)
fingerprint=${fingerprint#*=}; fingerprint=${fingerprint//:/}
requirement="identifier \"be.nick.wisperflow\" and certificate leaf = H\"$fingerprint\""
# Sign the SwiftPM resource bundles first, using their own bundle identifiers.
for bundle in "$app/Contents/MacOS/"*.bundle(N); do
    codesign --force --sign "$fingerprint" --keychain "$keychain" --timestamp=none "$bundle"
done
# Only the main app receives the explicit, certificate-pinned app requirement.
codesign --force --sign "$fingerprint" --keychain "$keychain" --timestamp=none \
    --identifier be.nick.wisperflow --requirements "=designated => $requirement" "$app"
codesign --verify --deep --strict --test-requirement "=$requirement" "$app"
unset signing_password
