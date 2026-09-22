# Aquarist — PLAN

## Scope

Aquarist is an iPhone-only native Swift (SwiftUI) app that maintains a per-tank append-only event ledger (water changes, test readings, doses, livestock events, equipment events, notes) and derives glanceable status deterministically. Local storage only; zero network by design. iPad and Android are out of scope (explicit opt-in only). Dual-screen (iPhone Duo) is a documented design target with a single migration seam, never a build dependency.

Out of scope: water-chemistry modelling, diagnosis or safety verdicts, plant/animal ID AI, OCR, retail/price data, controller/hardware automation, cloud sync, accounts, social features, aquaculture/veterinary claims.

## Architecture

```
┌─────────────────────────────────────────────┐
│ App target (SwiftUI, iPhone-only, TDF=1)    │
│  TankWallView · QuickLogSheets · HistoryView│
│  TestCaptureView · LivestockView · Settings │
│  TankWorkspaceLayout  ← dual-screen seam    │
├─────────────────────────────────────────────┤
│ AquaristStore (GRDB persistence)            │
│  schema migrations v1.. · fixture DB        │
├─────────────────────────────────────────────┤
│ AquaristKit (pure Swift, no UI, no GRDB)    │
│  Tank · TankEvent (append-only)             │
│  Derivations: daysSince, weeklyTotals,      │
│   lastDoseAge, trend (raw series) — all     │
│   unknown-safe, DST-safe calendar math      │
│  ReferenceBand (user text/values, verbatim) │
│  BackupCodec (versioned JSON) · CSVExport   │
└─────────────────────────────────────────────┘
```

- **AquaristKit** is a Swift Package with zero dependencies — the entire domain, all arithmetic, all derivations, unknown-safe semantics. Testable on Linux CI.
- **AquaristStore** is a separate package pinning GRDB (SQLite). Schema is versioned migrations; fixture DB committed for tests.
- **App target** is thin: views + view models over repositories. `TankWorkspaceLayout` is the one place that would ever grow dual-screen region mapping.

## Technology choices and rationale

| Choice | Rationale |
|---|---|
| Native Swift + SwiftUI | User directive: native Swift only; no cross-platform frameworks. SwiftUI gives accessible Dynamic Type behavior cheaply. |
| iOS 26 SDK / Xcode 26.0.1 (17A400) / Swift 6 | Mandated SDK floor; pinned in `toolchain.json`, CI-measured exactly. |
| GRDB (SQLite) | Deterministic local store with real migrations and queryable history; proven in sibling repos; pure-Swift-friendly tests on Linux. |
| Swift Package Manager for domain/store | Keeps UIKit/Xcode out of the testable core; Linux CI can run the domain suite. |
| Zero-network architecture | Privacy default and CI-enforceable invariant (empty egress allowlist gate). |

## Milestones and dependency order

1. **M1 Skeleton + CI** (issue #1) — Xcode project, `AquaristKit` package, pinned macOS CI, iPhone-only guards (`TARGETED_DEVICE_FAMILY=1` pre-build grep, `UIDeviceFamily == [1]` post-build check), zero-network gate. Blocks everything.
2. **M2 Domain core** (issue #2) — event model + derivations + unknown-safe semantics, swift-testing suite. Depends on M1.
3. **M3 Persistence** (issue #3) — GRDB schema v1, migrations, repository protocols + fakes, fixture DB. Depends on M2.
4. **M4 Primary workflow UI** (issue #4) — tank registry, tank wall, quick-log sheets. Depends on M3.
5. **M5 Accessible UI polish + dual-screen design doc** (issue #5) — VoiceOver/Dynamic Type pass, wet-hands tap targets, `TankWorkspaceLayout` seam + documented unfolded design. Depends on M4.
6. **M6 History & trends + livestock** (issue #6) — per-tank chronological ledger, raw-value trend charts, livestock roster events. Depends on M4.
7. **M7 Backup/export + release** (issue #7) — JSON backup/restore (previewed replace), CSV export, TestFlight upload via ASC Actions secrets with real signing evidence. Depends on M3–M6.

## Testing strategy

- **Domain:** swift-testing suite in `AquaristKit` — derivation edge cases (empty ledger, DST boundaries, unknown inputs, integer arithmetic for volumes/cents-free quantities), backup codec round-trips, reference-band verbatim echo. Runs on Linux CI (pinned Swift) and macOS CI.
- **Store:** migration up-tests against committed fixture DB; repository fakes for UI tests.
- **UI:** one launch XCUITest at skeleton; flow tests as views land.
- **Invariants as CI gates:** iPhone-only device family, bundle-ID prefix `com.infinityball.`, zero-network egress allowlist (empty), exact toolchain measurement.
- Honesty rule: Linux results are never presented as app build/archive/TestFlight evidence; those gates require Apple runners and real signing output.

## Packaging / distribution

- Ad-hoc archive on Apple CI for smoke; TestFlight via App Store Connect API using repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (secret names only, never values); bundle ID `com.infinityball.aquarist`.
- App Store record, signing certificates/profiles, and a processed TestFlight build are release gates that must show real tool output before being claimed.

## Risks

| Risk | Mitigation |
|---|---|
| Scope creep toward controller/automation | Hard non-goal; hardware integration requires a separate product decision. |
| Perceived medical/chemistry advice | Unknown-safe rendering; reference bands are user-owned text echoed verbatim; README + UI copy carry the hobby-log framing. |
| Toolchain drift in CI | Exact pin assertion; missing exact pin = blocker, never silent substitution. |
| Chart library temptation | MVP trend = raw per-record value series via SwiftUI Charts; no third-party deps. |

## Explicit non-goals

No iPad, no Android, no cloud, no accounts, no AI/OCR, no automation hooks, no social layer, no health/veterinary claims — as enumerated in README non-goals.
