#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ROAM_SIMULATOR_ID:?Set ROAM_SIMULATOR_ID to an available booted iPhone simulator UUID}"
work="${TMPDIR:-/tmp}/RoamJournalUIVerification"
phase="${1:-all}"
case "$phase" in
  all|build|test) ;;
  *) echo "Usage: $0 [all|build|test]" >&2; exit 2 ;;
esac
if [[ "$phase" != test ]]; then
  xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournal -configuration Debug -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -derivedDataPath "$work" CODE_SIGNING_ALLOWED=NO build
  xcrun simctl install "$ROAM_SIMULATOR_ID" "$work/Build/Products/Debug-iphonesimulator/RoamJournal.app"
fi
if [[ "$phase" != build ]]; then
  xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournalUITests -configuration Debug -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -destination-timeout 60 -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -derivedDataPath "$work" -resultBundlePath "$work/UITests-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO test
fi
