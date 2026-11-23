#!/bin/zsh
# Builds a Developer ID signed, notarized and stapled build/Fillet-<version>.zip.
#
#   FILLET_TEAM_ID=XXXXXXXXXX scripts/release.sh
#
# Needs Xcode signed in (Settings › Accounts) to an account on that team that may create Developer ID
# certificates, plus xcodegen. Xcode signs, uploads to Apple's notary service and waits for the ticket.
set -euo pipefail
cd "${0:A:h}/.."
team=${FILLET_TEAM_ID:?set FILLET_TEAM_ID to your Apple Developer team ID}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive=build/Fillet.xcarchive

xcodegen generate --quiet
rm -rf "$archive" build/export build/notarized
xcodebuild archive -project Fillet.xcodeproj -scheme Fillet -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    DEVELOPMENT_TEAM="$team" -allowProvisioningUpdates -quiet

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

# Signs with Developer ID and uploads to the notary service.
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist build/ExportOptions.plist \
    -exportPath build/export -allowProvisioningUpdates

# Wait for Apple's verdict, then export the stapled app.
for attempt in {1..40}; do
    if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath build/notarized 2>/dev/null; then break; fi
    echo "waiting for notarization… ($attempt)"
    sleep 30
done
app=build/notarized/Fillet.app
[[ -d $app ]] || { echo "notarization didn't finish; run again later or check Xcode's Organizer"; exit 1; }

xcrun stapler validate "$app"
spctl -a -vv -t exec "$app"
rm -f "build/Fillet-$version.zip"
ditto -c -k --keepParent "$app" "build/Fillet-$version.zip"
echo "release ready: build/Fillet-$version.zip"
