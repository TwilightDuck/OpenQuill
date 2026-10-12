#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product OpenQuill
binary_dir=$(swift build --show-bin-path)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
# Compile against the real private task owner without adding hooks to the shipped app.
cat Sources/OpenQuill/AppState.swift scripts/CancellationCheck.swift > "$temporary/AppState.swift"
sed -n -e '1,3p' -e '/^@MainActor$/,$p' Sources/OpenQuill/OpenQuillApp.swift > "$temporary/App.swift"
source_files=(Sources/OpenQuill/*.swift)
source_files=(${source_files:#Sources/OpenQuill/AppState.swift})
source_files=(${source_files:#Sources/OpenQuill/OpenQuillApp.swift})
swiftc -swift-version 6 -parse-as-library -I "$binary_dir" \
    -I .build/checkouts/FluidAudio/Sources/FastClusterWrapper/include \
    -I .build/checkouts/FluidAudio/Sources/MachTaskSelfWrapper/include \
    "${source_files[@]}" "$temporary/App.swift" "$temporary/AppState.swift" \
    "$binary_dir"/*.o -lc++ -o "$temporary/check"
"$temporary/check"
