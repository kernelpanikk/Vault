#!/bin/zsh
# Self-test of the vault engine (real hdiutil, throwaway vault in $TMPDIR).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macos15.0 Sources/Vault/Vault.swift Tests/main.swift -o build/selftest
build/selftest
