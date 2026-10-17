#!/bin/zsh
# Builds build/Vault.app. Usage: scripts/build-app.sh [--debug] [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

flags=(-O)
[[ " $* " == *" --debug "* ]] && flags=(-Onone -g -D DEBUG)

app=build/Vault.app
rm -rf $app
mkdir -p $app/Contents/MacOS
swiftc -swift-version 5 -target arm64-apple-macos15.0 -parse-as-library $flags Sources/Vault/*.swift -o $app/Contents/MacOS/Vault
cp Resources/Info.plist $app/Contents/
# Ad-hoc signature + Hardened Runtime (no Apple ID team on this Mac yet).
codesign --force --options runtime --sign - $app

if [[ " $* " == *" --install "* ]]; then
    rm -rf /Applications/Vault.app
    cp -R $app /Applications/
    echo "Installata in /Applications/Vault.app"
fi
du -sh $app
