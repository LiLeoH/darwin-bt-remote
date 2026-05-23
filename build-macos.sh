#!/usr/bin/env bash
PROJECT="BTRemote"

# nix-shell -p xcodegen swiftlint swiftformat xcbeautify --run "unset LD && ./build-macsos.sh"
xcodegen generate
xcodebuild \
    -project $PROJECT.xcodeproj \
    -scheme $PROJECT \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build | xcbeautify

APP=.build/DerivedData/Build/Products/Release/$PROJECT.app
codesign --force --sign - --entitlements $PROJECT/entitlements.plist $APP

rm -rf .build/$PROJECT-mac.app
cp -R $APP .build/$PROJECT-mac.app
