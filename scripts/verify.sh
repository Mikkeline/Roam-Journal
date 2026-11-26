#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work="${TMPDIR:-/tmp}/RoamJournalVerification"
mkdir -p "$work"
swift test --scratch-path "$work/SwiftPM"
xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournal -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "$work/DerivedData" CODE_SIGNING_ALLOWED=NO build
python3 scripts/release_check.py "$work/DerivedData/Build/Products/Release-iphonesimulator/RoamJournal.app"
