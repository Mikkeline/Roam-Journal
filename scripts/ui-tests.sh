#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ROAM_SIMULATOR_ID:?Set ROAM_SIMULATOR_ID to an available booted iPhone simulator UUID}"
work="${TMPDIR:-/tmp}/RoamJournalUIVerification"
xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournal -configuration Debug -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -derivedDataPath "$work" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$ROAM_SIMULATOR_ID" "$work/Build/Products/Debug-iphonesimulator/RoamJournal.app"
xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournalUITests -configuration Debug -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -derivedDataPath "$work" CODE_SIGNING_ALLOWED=NO test
