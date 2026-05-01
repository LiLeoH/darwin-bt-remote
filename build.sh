#!/usr/bin/env bash
PROJECT="BTRemote"

# nix-shell -p xcodegen swiftlint swiftformat xcbeautify --run "unset LD && ./build.sh"
xcodegen generate
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
