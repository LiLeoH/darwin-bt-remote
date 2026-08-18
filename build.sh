#!/usr/bin/env bash
# nix-shell -p xcodegen swiftlint swiftformat xcbeautify --run "unset LD && ./build.sh"

set -e
ci_scripts/ci_post_clone.sh

swiftformat --lint .
# Homebrew's swiftlint 0.65.0 ships a standalone binary without the
# sourcekitdInProc.framework it loads at startup, causing a fatal crash.
# SWIFTLINT_DISABLE_SOURCEKIT=1 bypasses SourceKit loading so linting runs.
# NOTE: this disables SourceKit-based analyzer rules (e.g. unused_import).
SWIFTLINT_DISABLE_SOURCEKIT=1 swiftlint lint --strict
PROJECT="BTRemote"

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

# iOS build & .ipa packaging (skipped if destination not available)
if xcrun --sdk iphoneos --show-sdk-path &>/dev/null; then
    ios_log=$(mktemp)
    set +e
    xcodebuild \
        -project "$PROJECT.xcodeproj" \
        -scheme "$PROJECT" \
        -configuration Release \
        -sdk iphoneos \
        -destination "generic/platform=iOS" \
        -derivedDataPath .build/DerivedData \
        CODE_SIGNING_ALLOWED=NO \
        build > "$ios_log" 2>&1
    ios_exit=$?
    set -e
    if [ $ios_exit -eq 0 ] && [ -d ".build/DerivedData/Build/Products/Release-iphoneos/$PROJECT.app" ]; then
        cat "$ios_log" | xcbeautify
        rm -rf .build/Payload *.ipa
        mkdir -p .build/Payload
        cp -R ".build/DerivedData/Build/Products/Release-iphoneos/$PROJECT.app" .build/Payload/
        cd .build/
        /usr/bin/zip -qry "../$PROJECT.ipa" Payload
    fi
    rm -f "$ios_log"
fi
