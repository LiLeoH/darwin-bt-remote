#!/usr/bin/env bash
PROJECT="BTRemote"

# nix-shell -p xcodegen swiftlint swiftformat xcbeautify --run "unset LD && ./build.sh"
for file in company_ids service_uuids; do
    [ -f "BTRemote/Resources/$file.json" ] || curl -fsSL -o "BTRemote/Resources/$file.json" "https://raw.githubusercontent.com/NordicSemiconductor/bluetooth-numbers-database/master/v1/$file.json"
done
xcodegen generate

# macOS
xcodebuild \
    -project $PROJECT.xcodeproj \
    -scheme $PROJECT \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build | xcbeautify
codesign --force --sign - --entitlements $PROJECT/entitlements.plist .build/DerivedData/Build/Products/Release/$PROJECT.app

# iOS
xcodebuild \
    -project $PROJECT.xcodeproj \
    -scheme $PROJECT \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build | xcbeautify
rm -rf .build/Payload *.ipa
mkdir -p .build/Payload
cp -R .build/DerivedData/Build/Products/Release-iphoneos/$PROJECT.app .build/Payload/
cd .build/
/usr/bin/zip -qry ../$PROJECT.ipa Payload
