# Enabling iCloud in a supported build

The default RoamJournal build is local-only so it works with the current Personal Team. Xcode reported that this team cannot provision iCloud and Push Notifications. The code remains available, but the default build deliberately does not request those capabilities.

For an iCloud-enabled build:

1. Choose an Apple Developer Program team that supports iCloud. Keep the bundle identifier if preserving this installation’s data is necessary; changing it creates a different app container and Keychain namespace.
2. In Signing & Capabilities, add iCloud, select CloudKit, and register/select a container owned by that team. Let Xcode produce the matching provisioning profile and entitlements. Do not use a placeholder container as though it were registered.
3. Set the Info.plist custom key `RoamCloudContainerIdentifier` to that exact container identifier, for example your registered replacement for `iCloud.org.example.portfolio.TrailVault`.
4. Only after capabilities and signing are configured, set the Boolean Info.plist key `RoamCloudBuildEnabled` to true. The code uses this flag to avoid constructing a CloudKit container in unsupported builds.
5. Build and run on a Face ID-enabled device signed into iCloud. Confirm the Settings disclosure, complete Face ID, and wait for a successful sync.
6. Test a second device with the same account/container/environment. Deploy the development schema to Production before TestFlight/App Store use.

Cloud schema: private database, custom zone `RoamJournalV1`, record type `JournalItemV1`.

| Field | Type |
| --- | --- |
| `encryptedPayload` | Asset containing AES-GCM ciphertext |
| `payloadKey` | Encrypted Bytes |
| `ownerID` | Encrypted String |

Create encrypted fields as encrypted fields from the beginning. Do not query or index them. Reference: [Apple CloudKit encryption](https://developer.apple.com/documentation/cloudkit/encrypting-user-data).

Acceptance tests: upload/download notes and photo copies, offline edits to different entries, conflicting edits to the same entry without duplicate conflict copies, deletion while another device is offline, edits during an in-progress request, pagination, account changes, disabled sync, quota/network errors, and restoration after reinstall on a disposable test installation. Use fictional data.

Remote edits/deletions must not dismiss an active draft. They wait until the trip closes; deletion notices should tell the user to copy important text first. Face ID must remain required on each device and after backgrounding.

Live CloudKit sync and production schema deployment have not been verified. The archive rewrites the whole notebook and retains sync payload metadata, so large photo libraries require additional storage/performance work. Sync is not a versioned backup. Turning it off keeps cloud copies, and a network request already underway may finish. Missing/reset cloud zones halt automatic recovery rather than deleting data without confirmation.
