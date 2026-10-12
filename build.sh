#!/bin/zsh
# Compiles Kandela and assembles the .app bundle (ad-hoc signature, for local use).
# --install: also replaces /Applications/Kandela.app and restarts Kandela from there.
set -e
cd "$(dirname "$0")"

install=false
case "$1" in
    "") ;;
    --install) install=true ;;
    *) echo "usage: $0 [--install]" >&2; exit 2 ;;
esac

# Every NSLocalizedString key in the source must be translated in every language.
for strings in Resources/*.lproj/Localizable.strings; do
    grep -o 'NSLocalizedString("[^"]*"' Sources/main.swift | cut -d'"' -f2 | while read -r key; do
        grep -qF "\"$key\" =" "$strings" || { echo "Missing \"$key\" in $strings" >&2; exit 1; }
    done
done

APP=Kandela.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# build number = commit count; KandelaCommit = short hash (+ "-dirty" when tracked files differ from it)
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
git diff --quiet HEAD 2>/dev/null || commit="$commit-dirty"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" \
    -c "Add :KandelaCommit string $commit" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # rebuilt by Tools/make-icon.swift
cp -R Resources/*.lproj "$APP/Contents/Resources/"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Kandela"
codesign --force --sign - "$APP"

echo "OK: $PWD/$APP ($commit)"

if $install; then
    DEST=/Applications/Kandela.app
    # Kandela has no documents to lose, so the running copy (wherever it was opened
    # from) is quit and the new one opened: otherwise the old build keeps running.
    running=false
    if pgrep -xq Kandela; then
        running=true
        osascript -e 'tell application id "br.com.kogut.kandela" to quit'
        for i in {1..20}; do pgrep -xq Kandela || break; sleep 0.25; done
        pgrep -xq Kandela && { echo "Kandela did not quit; nothing was installed." >&2; exit 1; }
    fi
    [[ -d "$DEST" ]] && rm -r "$DEST"
    ditto "$APP" "$DEST"
    # re-register: refreshes the icon Launch Services had cached from the old copy
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
    echo "Installed: $DEST"
    if $running; then
        open "$DEST"
        echo "Kandela restarted from $DEST"
    fi
else
    echo "To run: open $PWD/$APP"
fi
