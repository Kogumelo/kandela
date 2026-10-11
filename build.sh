#!/bin/zsh
# Compiles Kandela and assembles the .app bundle (ad-hoc signature, for local use).
set -e
cd "$(dirname "$0")"

APP=Kandela.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # rebuilt by Tools/make-icon.swift
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Kandela"
codesign --force --sign - "$APP"

echo "OK: $PWD/$APP"
echo "To run: open $PWD/$APP"
