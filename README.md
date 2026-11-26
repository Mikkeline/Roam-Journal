# Roam Journal

A private iOS travel journal with trip plans, notes, saved places, photo copies, and Face ID access.

## Open and run

Open `RoamJournal.xcodeproj`, choose the **RoamJournal** scheme and your iPhone or an iPhone simulator, then press Command-R. The project uses Xcode 27.2; use the same or a compatible newer Xcode for its project format. Minimum iOS is 17.

**The default build is local-only and supports the configured Personal Team.** It has no active iCloud or Push Notifications entitlements. Face ID, photos, search, and encrypted local storage do not require those capabilities. The iCloud control is disabled in this build; see [ICLOUD_SETUP.md](ICLOUD_SETUP.md) for a supported developer-account build.

The project identifier is `dev.michelle.roamjornal`. Its Keychain service is the bundle identifier plus `.notebook`, account `archive-key-v1`. Data from a different app identifier is not automatically migrated. The project and scheme are now RoamJournal; the installed display name is Roam Journal. Do not uninstall an existing app to fix a build issue: local-only notes can be lost by uninstalling.

## Features

- Travel essentials per trip: outbound/return flights, private document copies, and a packing checklist.
- Trip cards, travel status, dates, duration, entry counts, destination search, filters, and sorting.
- Dated notes and places, day-grouped journals, photo thumbnails, and text sharing.
- Apple Maps place search, selected addresses and coordinates, optional map previews, and Open in Apple Maps.
- A Tiffany-turquoise Roam Journal app icon.
- Trip and entry editing, explicit Save/Cancel, draft discard confirmation, keyboard dismissal, and confirmed deletion.
- Individual photo selection and resized JPEG copies without original image metadata.
- Face ID-only trip access. There is no in-app passcode or Touch ID fallback.
- Optional CloudKit sync implementation, gated off in the default Personal Team build.

Create a trip to open its Face ID gate. Successful authentication grants access to that trip. Leaving it, explicitly locking, or backgrounding the app revokes access. Late authentication callbacks cannot reopen a locked trip. The privacy window covers inactive content and presented editors. Reauthentication preserves in-memory drafts; Close trip explicitly discards unsaved edits.

Home search checks destinations only. Trip names, dates, status, and entry counts remain visible without authentication. Notes, photos, editing, deletion, and sharing are reached through authenticated destinations.

## Find and save a place

Open an unlocked trip, tap **Save a place**, then **Search Apple Maps**. Enter a landmark, address, hotel, or cafe (include a city for better results), then submit with Search. Choose a result or map pin, tap **Use this place**, and tap **Save** in the entry editor. Search selection updates the draft and does not save until that final action.

The selected name, address, latitude, and longitude are encrypted with the entry. Existing manually entered places and older notes still load without a location. Replace or remove the location while editing; manual place entry remains available when offline.

Saved addresses and coordinates are readable offline. Search and map tiles require internet. Saved maps show by default, with a Hide map option; Open in Apple Maps opens the selected point in Apple Maps. Tap Use my location in place search to request When In Use permission and focus searches nearby. Denied access leaves manual search available, with an Open Settings link. There is no background tracking. Search queries and displayed map locations use Apple's services; journal text is not included in searches. Explicit text sharing now includes saved addresses and map links, without photos.

The launcher icon is `RoamJournal/Assets.xcassets/AppIcon.appiconset/RoamJournal-Tiffany.png`: an opaque 1024×1024 PNG with a Tiffany-turquoise background, ivory journal, and apricot pin. iOS applies the icon mask.

## Storage and security

`NotebookArchive` serializes a versioned notebook and encrypts it with AES-256-GCM, fresh nonces, atomic writes, and iOS complete file protection. Its random key uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in the Keychain. Existing storage remains at Application Support/PrivateNotebook/notebook.vault. Startup recovery writes a separate UUID directory and verified active-directory pointer, preserving the damaged archive and its key.

Existing version-1 journals without sync metadata still decode. Invalid saves do not replace the previous archive. An unreadable or undecryptable archive is preserved and an error is shown.

Face ID is an application access gate, not biometric access control on the encryption key. The app can decrypt local content while the device is unlocked and holds data in memory. It does not prevent screenshots or inspection of a compromised runtime.

The device-only archive is excluded from device backups. With sync off, device loss or app deletion can lose the journal. Share important trip text as an extra copy; sharing produces unencrypted text without photos and is not a complete backup.

## Optional sync implementation

A supported iCloud build requires explicit user confirmation and Face ID before enabling uploads. It uses a private CloudKit zone, fresh AES-GCM payload keys in CloudKit encrypted fields, and encrypted asset transfers. The local archive key is never synchronized.

Sync runs after saves, activation, periodic foreground checks, and manual requests. The first pass loads the custom zone; later checks use an in-memory change token. Independent entry changes merge. Competing entry versions are retained as additional Other version entries. Concurrent trip metadata retains one deterministic version. Deletion records prevent stale edits resurrecting deleted items.

Changes affecting an open trip wait until it is closed, preserving active editors. Account changes pause sync and the local journal remains bound to its original account. Cloud errors keep local copies and allow retry. Sync is not historical backup or push-driven background sync. Live two-device sync remains unverified.

## Code and tests

| Path | Purpose |
| --- | --- |
| `RoamJournal/RoamJournalApp.swift` | Entry point, lifecycle, foreground sync scheduling |
| `RoamJournal/ContentView.swift` | Trip list, journal, entry detail, search and navigation |
| `RoamJournal/JournalDesign.swift` | Cards, theme, settings, privacy, previews |
| `RoamJournal/NotebookEditors.swift` | Drafts, validation, photo handling |
| `RoamJournal/PlaceSearch.swift` | Apple Maps search, result selection, stored-place maps |
| `RoamJournal/Core/SavedPlace.swift` | Codable place data, coordinate validation, safe Apple Maps links |
| `RoamJournal/NotebookStore.swift` | Keychain, archive, Face ID, sync coordination |
| `RoamJournal/TripLock.swift` | Access gates and scene privacy window |
| `RoamJournal/CloudJournalService.swift` | Optional private CloudKit transport and build gate |
| `RoamJournal/Core` | Codable models, encryption, authorization and sync merge logic |
| `Examples` | Route/C++ learning example, outside the iOS app |
| `Tests` | 82 core and legacy XCTest cases |

Run core tests with `swift test` on macOS 14 or later with Swift 6 or later. The tests cover encrypted persistence, corruption, legacy decoding, sync convergence, conflict copies, deletion, invalid records, and stale authorization. They do not replace device/Face ID or live CloudKit testing.

Physical-device memory benchmarks, Files-provider round trips, and broader accessibility walkthroughs remain release acceptance checks. Development included AI assistance; no license is selected.

## Travel essentials

Unlock a trip, then open **Flights, documents & packing**. The hub links to separate Flights, Packing checklist, and Travel documents screens. Flight cards show outbound/return journeys and connections, departure/arrival times in each selected airport time zone, terminals, airline, and booking reference. Use Edit to change flights and Save/Cancel to finish. Arrival cannot precede departure, and a connection cannot depart before the preceding arrival. There is no live flight-status or schedule API integration.

Packing changes save immediately: add an item, tap its circle to mark packed/unpacked, or swipe to rename/remove it. Remaining items appear before packed items, with a completion count. Add suggested essentials or save the current list as a reusable named template. Applying a template adds only missing names, preserves existing ticks, and starts new items unpacked. Templates are device-local, encrypted in the notebook and included in full backups; they do not sync through CloudKit. This is a checklist without scheduled notifications.

Import PDF, image, and UTF-8 text documents from Files. Limits are 10 MB per file, 30 MB total and 20 files per trip. Copies are stored in encrypted attachment sidecars; previews use in-memory data rather than creating app-owned plaintext temporary files. Originals in Files are unchanged. Files stored only in a cloud provider may need downloading first. Existing Face ID/privacy-cover behavior applies to essentials and document previews. Travel essentials are excluded from the existing Share trip text action.

Older trips decode without essentials. Essentials are included in trip metadata for the optional CloudKit implementation; this build remains local-only. Concurrent essentials edits use the existing trip-metadata conflict winner, rather than merging individual checklist items or documents. Live CloudKit syncing of attachments has not been verified.

## Reliability and encrypted recovery

**Settings → Backup & restore** prepares a complete encrypted journal backup after fresh Face ID authentication. Save the displayed random 64-character recovery code separately, confirm you have kept it, then save the `.roambackup` file to Files. Every prepared backup has a new code. There is no password-based key derivation: the recovery code represents a randomly generated 256-bit AES-GCM key, and is not included in the file. Losing the code makes that backup unreadable. This manual backup does not require iCloud entitlement or an API subscription.

To restore on this or another Face ID device, enter the code, choose the file, check the verified trip/entry counts, and confirm **Restore as additional trips**. Fresh Face ID is required before applying it. Existing trips remain. Restored trips and entries get new IDs; importing twice creates duplicates. Sync-account state is excluded from backups, and restored trips join the destination journal's current sync state if enabled. New streaming backups support up to 2 GB total, 16 MB of metadata, and 30 MB per attachment. Legacy backup imports remain capped at 250 MB. This is not an automatic scheduled backup.

New local saves use format `RJAR3`: authenticated encrypted metadata plus encrypted, keyed content-addressed attachment files. Photos/documents (including binary data held by sync records) are externalised by the storage codec with explicit Codable attachment references in local models; portable legacy backups and optional cloud payloads are materialized at their boundaries. Unchanged attachment ciphertext is reused. Loading, JSON work, encryption, validation, and disk writes run in a persistence actor rather than the UI actor. The journal publishes only after a successful write; overlapping commands queue and resolve against the latest state. Opening loads metadata only; authenticated attachments load on demand, with bounded raw-data and thumbnail caches. Backup frames encrypt one attachment at a time.

Older inline and RJAR2 archives still load. RJAR2 references upgrade without loading binary payloads. The first successful save migrates them, retains an encrypted `.legacy-backup`, and writes attachment files before atomically committing the new metadata. A rolling encrypted `.previous` snapshot and its referenced attachments are retained; other unused sidecars are cleaned up after commit. These recovery files have no automatic restore UI and are not forensic erasure. Older app versions cannot open the new format. Do not roll back to an old build against migrated data without a recovery plan.

One notebook store is owned by the app and shared across windows. Persistence is serialised; trip/entry editors compare their original saved content before replacing it, preventing stale windows from overwriting newer edits or resurrecting deleted items. Scene presence is aggregated and each inactive window has its own privacy cover. Leaving/backgrounding a window can lock the shared trip session, so another window may need Face ID again. Physical-device multiwindow and file-provider checks remain outstanding.

## Offline airport selection and feature boundaries

In **Flights → Edit**, use **From airport** or **To airport** on any leg. Search the 7,918-airport offline list by name, city, IATA or ICAO code. Examples: `KUL`, `WMKK`, `PVG Shanghai`, `KLIA T1`, `KLIA T2`, and `KLIA2`. KLIA terminal aliases select KUL with Terminal 1 or 2; other results leave the terminal for manual entry. Selecting an airport fills its name/code and time zone. Time zones can also be selected manually. Changing a time zone preserves the instant and updates the displayed local time, so verify it against the ticket. Older flight records retain their original dates and use device-timezone display until a zone is selected.

The bundled reference dataset is an IATA-coded subset of mwgg/Airports, with license and credits shipped in the app. See AIRPORT_DATA.md for provenance. No API key, subscription, location permission, or internet is needed for airport selection. This reference list does not fetch airline schedules or guess the terminal from a flight number.

Responsibilities are separated: pure `FlightItinerary`, `AirportCatalog`, `EssentialsChange`, and `PackingTemplate` models/rules live in Core; the store authorizes and persists typed edits; flight, packing, document, and navigation screens own separate UI flows. Airport loading and document importing have small injectable protocols, with bundled/Files implementations. Flight and document draft saves compare only their own section against the original, preserving independently changed sections while rejecting stale edits to the same section. Cloud sync retains its existing whole-trip-metadata conflict policy.

## Airline detection from flight numbers

Every flight leg can fill the airline offline from an IATA or ICAO prefix plus a flight number. Examples: `MU8642` / `CES8642` → China Eastern Airlines; `MH123` → Malaysia Airlines; `AK123` → AirAsia; `D7505` → AirAsia X; `OD123` → Batik Air Malaysia. Whitespace, hyphens, lowercase, digit-containing airline codes (for example `6E`, `3U`), and a single operational suffix letter are handled. This uses a snapshot of 90 airlines, not a live API or an exhaustive airline database.

The airline field remains editable. Automatically filled values follow subsequent flight-number changes; manual overrides are retained. A Use detected airline button lets the user explicitly replace an override. Unknown, incomplete, malformed, or ambiguous numbers do not guess an airline; previous automatic values clear when no longer applicable. Optional provenance is stored with flight details, preserving older records and behavior across saves. A marketing code does not guarantee the operating carrier on a codeshare. No airports, terminal, date, flight status, or flight schedule are inferred from the airline prefix.

The pure FlightNumber/AirlineCatalog types own parsing and unique matching; the injectable AirlineCatalogLoading boundary supplies bundled data outside the UI thread. Source: AviationShop/airline-codes (86 records), CC0 1.0, plus four app-maintained additions checked against CAAM/IATA operator listings on 26 November 2026. License and provenance ship in Resources/AirlineData-LICENSE.txt and are readable from Flights → Airline reference data.

## Recovery, ticket scanning, and release preparation

Startup failures now offer **Recover from encrypted backup** without opening the damaged journal. A verified restore writes a separate archive/key and promotes its directory pointer only after validation. It preserves the damaged files. Normal backup restore is additive, including templates and unexpired Recently Deleted copies with remapped parent links.

Deleting a trip or entry retains an encrypted recovery copy for 30 days. Settings → Recently Deleted requires fresh Face ID to reveal names, restore copies, or empty it. Restores use new identities to avoid sync tombstones. Expiry is applied on open/save/export; older rolling snapshots and exported backups can retain data until removed separately.

Flights → Scan ticket reads a selected PDF/image with Vision on the device, offers known flight/airport candidates and unambiguous dates, and requires review before replacing flight fields. It reads at most 10 PDF pages and downsamples images. Airport time zones are required to apply extracted local times. OCR is a convenience, not flight-status verification.

Travel documents support filename search, categories, rename, and authenticated lazy previews. Settings → Airport & airline data shows reference dates/counts and manually downloads validated public source updates. Offline bundled lists remain the fallback; journal data is never included in those requests.

The backup screen records the last successful Files save. Privacy policy is available in Settings, and a matching page is prepared at `Site/privacy/index.html` for hosting. PrivacyInfo.xcprivacy declares tracking/data collection and required-reason APIs for this local-only build. No fake public policy/support links have been configured.

Run `bash scripts/verify.sh` for core tests, Release simulator compilation, and bundled privacy/resource checks. Run `ROAM_SIMULATOR_ID=<UUID> bash scripts/ui-tests.sh` on a booted iPhone simulator for isolated UI tests. The workflow runs both. Use the main RoamJournal scheme for normal app development; the separate RoamJournalUITests scheme launches the already installed app by its existing bundle ID.

The project has not been uploaded to TestFlight or published.
