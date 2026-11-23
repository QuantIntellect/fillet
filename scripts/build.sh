#!/bin/zsh
# Builds build/Fillet.app (universal: Apple silicon + Intel), ad hoc signed.
#
#   scripts/build.sh            build only
#   scripts/build.sh --install  build, copy to /Applications and (re)launch
#   scripts/build.sh --zip      build and make build/Fillet-<version>.zip for a GitHub release
set -euo pipefail
cd "${0:A:h}/.."

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Fillet

app=build/Fillet.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Fillet"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "built $app ($version)"

for arg in "$@"; do
    case $arg in
    --install)
        osascript -e 'quit app "Fillet"' 2>/dev/null || true
        pkill -x Fillet 2>/dev/null || true
        sleep 1
        rm -rf /Applications/Fillet.app
        ditto "$app" /Applications/Fillet.app
        open /Applications/Fillet.app
        echo "installed /Applications/Fillet.app"
        ;;
    --zip)
        rm -f "build/Fillet-$version.zip"
        ditto -c -k --keepParent "$app" "build/Fillet-$version.zip"
        echo "zipped build/Fillet-$version.zip"
        ;;
    esac
done
