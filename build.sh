#!/bin/zsh
# Compiles Kandela and assembles the .app bundle (ad-hoc signature, for local use).
set -e
cd "$(dirname "$0")"

# Every NSLocalizedString key in the source must be translated in every language.
for strings in Resources/*.lproj/Localizable.strings; do
    grep -o 'NSLocalizedString("[^"]*"' Sources/main.swift | cut -d'"' -f2 | while read -r key; do
        grep -qF "\"$key\" =" "$strings" || { echo "Missing \"$key\" in $strings" >&2; exit 1; }
    done
done

APP=Kandela.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # rebuilt by Tools/make-icon.swift
cp -R Resources/*.lproj "$APP/Contents/Resources/"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Kandela"
codesign --force --sign - "$APP"

echo "OK: $PWD/$APP"
echo "To run: open $PWD/$APP"
