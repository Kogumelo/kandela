#!/bin/zsh
# Compila o Kandela e monta o bundle .app (assinatura ad-hoc, uso local).
set -e
cd "$(dirname "$0")"

APP=Kandela.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # refeito por Tools/make-icon.swift
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Kandela"
codesign --force --sign - "$APP"

echo "OK: $PWD/$APP"
echo "Para rodar: open $PWD/$APP"
