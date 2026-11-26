#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work="${TMPDIR:-/tmp}/RoamJournalUIVerification"
phase="${1:-all}"
case "$phase" in
  all|build|install|test) ;;
  *) echo "Usage: $0 [all|build|install|test]" >&2; exit 2 ;;
esac
if [[ "$phase" == all || "$phase" == build ]]; then
  xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournal -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath "$work" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
fi
if [[ "$phase" != build ]]; then
  : "${ROAM_SIMULATOR_ID:?Set ROAM_SIMULATOR_ID to an available booted iPhone simulator UUID}"
fi
if [[ "$phase" == all || "$phase" == install ]]; then
  xcrun simctl install "$ROAM_SIMULATOR_ID" "$work/Build/Products/Debug-iphonesimulator/RoamJournal.app"
fi
if [[ "$phase" == all || "$phase" == test ]]; then
  xcodebuild -project RoamJournal.xcodeproj -scheme RoamJournalUITests -configuration Debug -destination "platform=iOS Simulator,id=$ROAM_SIMULATOR_ID" -destination-timeout 60 -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -derivedDataPath "$work" -resultBundlePath "$work/UITests-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO test
fi
