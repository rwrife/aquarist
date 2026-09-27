# Aquarist

**Pitch:** Local-first iPhone aquarium log for hobbyists: per-tank water-change ledgers, test readings with trends, dosing and livestock records, and a glanceable tank wall — no accounts, no cloud.

Aquarist is a native Swift (SwiftUI) iPhone app that keeps the operational truth of a fish or planted tank in one place: when water was last changed and how much, what the test kit said, what was dosed and when, and what lives in the tank. A hobbyist with one nanotank or a shelf of six gets an instant at-a-glance status wall and a deterministic history — without subscriptions, social feeds, or anyone else's servers.

## Motivation

Aquarium keeping fails on forgotten maintenance, not on exotic equipment. A missed water change, an unnoticed nitrate climb, or a dosing schedule drifted off causes algae blooms, livestock loss, and deflated hobbyists. Existing apps are account-gated, ad-laden, cloud-synced, or bundle gear automation the hobbyist didn't ask for. The hobbyist's real questions — *when did I last change this tank's water? is ammonia trending up? what did I add and when?* — are answerable from a local event ledger, and the answers should be glanceable in ten seconds at the tank with wet hands.

## Target users

- Freshwater and saltwater hobbyists with one to several display tanks (fish, shrimp, planted, reef-in-progress).
- Breeders and shutdown-cycle keepers who need per-container history across many small vessels.
- Anyone who wants honest maintenance history without an account, a cloud tier, or an ad wall.

Not intended for: public aquariums, aquaculture operations, laboratory aquaculture, or veterinary/fish-health treatment (see non-goals).

## Concrete use cases

1. **At the tank (folded, one-handed):** open the tank wall, see each tank's last-water-change age and status band, tap one tank, log a 25% water change in three taps, mark the filter rinse, done.
2. **Test day:** enter ammonia/nitrite/nitrate/pH readings from your liquid test kit (user-owned reference bands, unknown-safe rendering), see the trend chart for that tank, spot nitrate climbing toward the user's own reminder threshold.
3. **Dosing:** keep a per-tank supplement schedule (fertilizer, bacterial supplement, salt mix top-off), one-tap dose events, and a per-dose history so a "what did I dose yesterday?" question has an answer.
4. **Livestock:** a per-tank roster with added/removed/observed dates and quantities — "the cories arrived 2026-04-02; three shrimp got moved to the grow-out on 2026-08-11" — no barcodes, no social.
5. **Weekend review (unfolded):** tank wall on one display as a persistent control surface, the selected tank's ledger and trend charts on the other; scroll and selection continuity across the fold.

## How to use (intended end-to-end workflow)

1. Create a tank: name, volume (exact or approximate), type (freshwater/saltwater), start date.
2. Log events against it as life happens: water change, test reading, dose, medication (user-owned note), livestock add/remove, equipment change, note.
3. Check the tank wall for status bands (derived only from your own events and thresholds).
4. On test day, read from your own kit and enter values; Aquarist plots and interpolates nothing it cannot derive, and never labels a value safe or toxic — reference bands are the user's own text.
5. Export any or all tanks as JSON backup or CSV history at any time; restore from backup is previewed and replaces only what the user confirms.

## MVP feature list

- Tank registry with volume, type, start date, optional notes.
- Append-only per-tank event ledger: water change, test reading, dose, livestock event, equipment event, note.
- Deterministic derivations with unknown-safe semantics: days-since-water-change, day streaks, DST-safe weekly totals, last-dose age, per-parameter reading trend (per-record values, no smoothing).
- User-owned reference bands and reminder thresholds as plain text/values — echoed verbatim, never interpreted as advice.
- Glanceable tank wall (status bands + key ages per tank).
- Per-tank history view: chronological ledger + per-parameter trend charts.
- Local storage only, JSON backup/restore (previewed replace) and CSV export via the Files app.
- Accessibility: Dynamic Type, VoiceOver labels on all status glyphs, large tap targets for wet-hands use.

## Non-goals

- No water-chemistry model, diagnosis, or "safe/toxic/advise" verdicts — a reading is the user's number against the user's own band; unknown renders unknown.
- No fish or plant identification AI, no photo recognition.
- No camera/OCR reading capture, no barcode/retail integration, no price or store data.
- No equipment automation, controller integration, BLE/Wi-Fi probes, or actuators of any kind.
- No social feed, community, cloud sync, accounts, analytics, or ads.
- No aquaculture, veterinary, or medical-claim features; this is a hobby log, not fish-health advice.
- No Android, no native iPad support (see platform scope).

## Privacy, permissions, and data storage

- All data lives on-device (local SQLite/GRDB store); there is **zero network access by design** — a CI-enforced zero-network gate.
- No accounts, no push, no tracking, no third-party SDKs.
- No permissions required beyond none by default: no camera, no microphone, no location, no contacts. Backup/export goes through the user-driven Files app share sheet, which is explicit user action.
- Backup files are plain, user-readable JSON/CSV owned by the user; nothing is uploaded anywhere.

## Platform scope (iPhone-only, native Swift)

- **Native Swift (SwiftUI) iPhone-only app** built and CI-tested with the **iOS 26 SDK or newer** (see `toolchain.json`).
- **No Android and no native iPad support.** Android is not a roadmap item; iPad support requires explicit user opt-in. `TARGETED_DEVICE_FAMILY = 1` in every app-target configuration, verified `UIDeviceFamily == [1]` in the built app on Apple CI.
- Cross-platform/hybrid frameworks (Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity) are prohibited in this repository's code, CI, and tooling.

## iPhone Duo dual-screen design target

The dual-screen experience is a documented design target and migration path, **not a dependency on unavailable fold APIs**. Aquarist ships today as a standard iPhone app; the dual-screen value story is designed around a single layout seam:

- **Folded (today):** one-handed tank wall and quick-log sheets sized for wet-hands use at the tank.
- **Unfolded (design target):** tank wall becomes a persistent control surface on one display while the selected tank's ledger, trend charts, and livestock roster occupy the other — the canonical master-detail span, plus unfolded session-style test-day capture (keypad + live ledger side by side).
- **Migration seam:** `TankWorkspaceLayout` is the single view that maps workspace modes to screen regions. Today it resolves to the existing single-pane NavigationStack; a future native dual-screen API layer would implement the same mode vocabulary (wall/control-surface vs detail/ledger, selection + scroll continuity) without touching the domain layer. No unavailable fold/SDK APIs are used or assumed.

## Bundle identifier and App Store Connect

- Bundle ID: `com.infinityball.aquarist` (set as `PRODUCT_BUNDLE_IDENTIFIER` when the Xcode project lands; CI asserts the prefix and never allows another).
- App Store Connect bundle ID registration: **CREATED** (success) at scaffold time.
- GitHub Actions signing secrets configured on this repository (names only): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (App Store Connect Team ID for signing/provisioning). Secret values are never stored in the repository, issues, or reports.

## Current status and milestones

Native skeleton (issue #1), `AquaristKit` domain core (issue #2),
`AquaristStore` persistence (issue #3), and the primary workflow UI (issue
#4) have landed: `Aquarist.xcodeproj` (app + UI-test targets, bundle id
`com.infinityball.aquarist`, `TARGETED_DEVICE_FAMILY = 1` in every
configuration), pure Swift 6 `Packages/AquaristKit`, GRDB/SQLite schema v2
`Packages/AquaristStore` with frozen migrations + committed fixture DB, and
the tank wall / registry / wet-hands quick-log UI (`App/`), plus CI
that measures the exact pinned toolchain, enforces iPhone-only pre-build grep
+ post-build `UIDeviceFamily == [1]`, runs a zero-network empty-allowlist gate,
and runs all package tests on Linux and macOS. See `docs/bootstrap-evidence.md`
for what is host-verified vs CI-authoritative.
**No device, archive, or TestFlight evidence exists yet.** Remaining backlog:

- [x] M0: idea, README/PLAN, toolchain pin, backlog
- [x] M1: Xcode project skeleton + native CI with toolchain pin + iPhone-only guards (issue #1)
- [x] M2: `AquaristKit` pure-Swift domain: event ledger, derivations, reference bands, unknown-safe semantics + tests (issue #2)
- [x] M3: GRDB persistence with versioned migrations, fixture DB (issue #3)
- [x] M4: tank wall + quick-log UI (issues #4, #6)
- [ ] M5: test-day capture + trends + livestock ledger (issue #6)
- [ ] M6: backup/restore + CSV export + privacy controls (issue #7)
- [ ] M7: TestFlight release with real signing evidence (issue #7)

## Development quickstart (once skeleton lands)

```bash
# Requires an Apple CI runner with the exact pinned toolchain (toolchain.json):
# Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6 mode.
xcodebuild -project Aquarist.xcodeproj -scheme Aquarist \
  -sdk iphoneos -destination 'generic/platform=iOS' build
xcodebuild -scheme AquaristKit-Package test
swift test --package-path Packages/AquaristStore
```
On Linux, `AquaristKit` and the GRDB-backed `AquaristStore` package tests run under a pinned Swift container (with `libsqlite3-dev`); the app target builds only on Apple runners. Never claim archive/device/TestFlight results from Linux source checks.

## License

MIT — see `LICENSE`.
