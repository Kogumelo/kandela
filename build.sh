#!/bin/zsh
# Compila o km-dimmer e monta o bundle .app (assinatura ad-hoc, uso local).
set -e
cd "$(dirname "$0")"

APP=km-dimmer.app
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/km-dimmer"
codesign --force --sign - "$APP"

echo "OK: $PWD/$APP"
echo "Para rodar: open $PWD/$APP"
