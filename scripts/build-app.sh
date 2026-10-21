#!/bin/zsh
# Builds build/Vault.app. Usage: scripts/build-app.sh [--debug] [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

flags=(-O)
[[ " $* " == *" --debug "* ]] && flags=(-Onone -g -D DEBUG)

app=build/Vault.app
rm -rf $app
mkdir -p $app/Contents/MacOS
# The macOS 27 SDK's SwiftUI macros need a compiler plugin the Command Line Tools don't ship: build against 26.
sdk=($(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | tail -1))
(( $#sdk )) && sdk=(-sdk $sdk)
swiftc -swift-version 5 -target arm64-apple-macos26.0 $sdk -parse-as-library $flags Sources/Vault/*.swift -o $app/Contents/MacOS/Vault
cp Resources/Info.plist $app/Contents/
mkdir -p $app/Contents/Resources
cp -R Resources/Icons Resources/Fonts Resources/*.lproj Resources/AppIcon.icns $app/Contents/Resources/
# Ad-hoc signature + Hardened Runtime (no Apple ID team on this Mac yet).
codesign --force --options runtime --sign - $app

if [[ " $* " == *" --install "* ]]; then
    rm -rf /Applications/Vault.app
    cp -R $app /Applications/
    echo "Installata in /Applications/Vault.app"
fi
du -sh $app
