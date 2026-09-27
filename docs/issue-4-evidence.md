# Issue #4 bring-up evidence

Dated record of what was actually verified for this milestone, and what
remains CI-only per the project's evidence rules.

## What this milestone adds

- `App/AquaristModel.swift`: `@Observable` app model over the `AquaristStore`
  repository protocols. Opens a real on-disk GRDB store under Application
  Support in production, and an in-memory store when launched with
  `-ui-testing` (deterministic XCUITest state, no test pollution of a real
  user database). Exposes `saveTank`, `append(_:to:summary:)`, and
  `undoLastLog()` — the last one appends a `.correction` event rather than
  mutating or deleting the original (append-only ledger contract preserved).
- `App/TankWallView.swift`: the glanceable tank wall. Each card shows a
  derived history-status band (`unknown` / `partial` / `recorded` — purely
  descriptive, never a safety/chemistry verdict), the water-change and
  last-dose key ages, and renders `.unknown` visibly distinct from a known
  age (secondary color + explicit "Unknown" text vs primary-color counted
  days). An undo banner surfaces the most recent log with one tap to retract
  it.
- `App/TankEditorView.swift`: create/edit a tank — name, volume (exact vs
  approximate, parsed through `TankVolume.parse` with an explicit
  "approximate" toggle in addition to inferred markers like `~`), type
  (freshwater/saltwater/brackish/other), start date, free-form notes.
- `App/QuickLogView.swift`: one sheet per event family (water change, test
  reading, dose, livestock) reachable from the tank detail screen in ≤3 taps
  (tank card → quick-log kind → Save), each with an optional-note field and
  no more than the minimum required inputs. Test-reading values are stored
  and echoed verbatim — the sheet copy says so explicitly.
- **Domain layer additions** (`Packages/AquaristKit`): `Tank.kind` and
  `Tank.notes` fields (registry requirement from the issue); a
  `TankEventPayload.correction(targetEventID:note:)` case implementing
  "Undo" as a new append-only ledger entry, plus `EventLedger.effectiveEvents`
  (events minus anything a later correction retracts) which every derivation
  now reads from instead of the raw `events` array. 4 new/updated domain
  tests (registry round-trip, correction round-trip + derivation retraction).
- **Store layer** (`Packages/AquaristStore`): schema **v2** migration adds
  `tanks.kind` / `tanks.notes` (`NOT NULL DEFAULT` so the frozen v1 fixture
  upgrades cleanly), `TankEventPayloadCodec` handles the new `.correction`
  case, and `readingSeries` now reads the tank's full ledger (via
  `events(for:)`) instead of a narrower SQL projection, so a correction can
  retract a reading from the trend series without deleting its row. 3 new
  store tests (registry round-trip, correction-retracts-reading,
  migration-preserves-defaulted-columns).
- `UITests/AquaristLaunchTests.swift`: replaces the skeleton launch smoke
  test with an end-to-end journey — launch → add tank → open its card → log
  a water change → detail shows "Water change: Today" → back on the wall the
  same key age is visible — plus a second test asserting the wall's key-age
  text still renders (non-empty, contains "Water change:") under AX5 Dynamic
  Type (`UICTContentSizeCategoryAccessibilityXXXL`, the exact raw UIKit
  value; the previous milestone's skill notes flagged the common
  spelled-out-word mistake here).

## Accessibility choices made in this pass

- Every status glyph (`Image(systemName:)`) carries an explicit
  `.accessibilityLabel` describing the status in words, never left to
  VoiceOver's raw SF Symbol name.
- Key ages (`Water change: …`, `Last dose: …`) use `.fixedSize(horizontal:
  false, vertical: true)` and no `lineLimit`, so they wrap instead of
  truncating at large Dynamic Type sizes.
- Quick-log entry points and the Undo button use a 56pt/52pt minimum tap
  target (`minHeight`) for wet-hands use.
- `TARGETED_DEVICE_FAMILY = 1` only; no iPad-specific sizing or layout code
  was introduced. All new views are plain `NavigationStack` / `Form` / plain
  `VStack`/`ScrollView` compositions with no size-class branching.

## Verification actually performed (Linux executor, 2026-09-27, no Xcode/simulator on host)

- `swift test --package-path Packages/AquaristKit` inside `swift:6.2-noble`
  (matching the CI Linux job image exactly): **28 tests in 9 suites passed**
  (26 pre-existing + 2 new: registry round-trip, correction/derivation
  retraction).
- `swift test --package-path Packages/AquaristStore` in the same container:
  **18 tests in 4 suites passed** (15 pre-existing + 3 new), including the
  committed v1 fixture database migrating cleanly through the new v2
  migration and the migrator's idempotency check.
- `swiftc -parse` on every new/changed file under `App/` and `UITests/` —
  syntax/parse clean. (Per the project's own CI-troubleshooting notes, this
  does **not** validate SwiftUI/XCTest type-checking, which requires the
  Apple toolchain; the app-target build and UI test run are CI-authoritative,
  not claimed here.)
- `bash scripts/check_zero_network.sh` — PASS, empty allowlist, scanned
  `App/`, `UITests/`, `Packages/*/Sources/`.
- `python3 -m unittest discover -s Scripts/tests` — 21 helper tests still
  pass (unchanged by this milestone).
- pbxproj object-ID closure probe (defined == referenced, all 24-hex ids) —
  clean, 46 defined / 46 referenced, no missing IDs, after adding the four
  new `App/` source files and the `AquaristStore` local package product
  dependency to the `Aquarist` target.
- iPhone-only pre-build grep (same check `Scripts/ci.sh` runs): every
  `TARGETED_DEVICE_FAMILY` setting in the four build configurations is
  exactly `1`; no `1,2` or `2` variant present.
- `git diff --check` — clean (no trailing whitespace / conflict markers).

## CI-pending claims (NOT claimed from this host)

- The actual Xcode build of the `Aquarist` app target (now with two Swift
  package product dependencies instead of one), the XCUITest run of both
  `AquaristLaunchTests` methods on a real simulator, the post-build
  `UIDeviceFamily == [1]` check, and any VoiceOver/Dynamic Type screenshot
  evidence are **CI-pending**: authoritative evidence is the macOS CI run
  for this PR's exact head SHA (`ios-ci-<sha>` artifact). No such run has
  been observed from this host.
- No physical-device, signed-archive, or TestFlight evidence exists or is
  claimed (issue #7 owns that).
- The AX5 Dynamic Type test asserts the key-age text still exists and reads
  as expected; it does not assert pixel-level non-truncation, which needs a
  real rendering pass on-device or in-simulator.

## Explicit non-claims

- No water-chemistry, safety, or diagnostic language was added anywhere in
  the new UI copy; `TankHistoryStatus` titles ("History unknown" / "History
  partial" / "Maintenance ages recorded") describe *data completeness*,
  never a chemistry verdict.
- Livestock roster and per-parameter trend charts (issue #6) and
  backup/CSV export (issue #7) are out of scope for this issue and are not
  touched here beyond the domain-level `correction` event type, which issue
  #6's roster/ledger derivations already read through `effectiveEvents`.
