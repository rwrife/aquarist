# Issue #5 bring-up evidence

Dated record of what was actually verified for this milestone, and what
remains CI-only per the project's evidence rules.

## What this milestone adds

- `Packages/AquaristKit/Sources/AquaristKit/Workspace/TankWorkspaceLayout.swift`:
  pure-domain workspace mode and continuity state machine.
  - `TankWorkspaceMode`: `.singlePane`, `.unfoldedTwoPaneTarget`.
  - `TankWorkspaceRegion`: `.wallControlSurface`, `.detailLedger`.
  - `TankWorkspaceContinuity`: tracks `selectedTankID`, `wallScrollAnchorTankID`, and
    `detailScrollAnchorEventID`.
  - `TankWorkspaceLayoutState`: manages visible regions and transitions while
    strictly preserving continuity state across fold simulation.
- `Packages/AquaristKit/Tests/AquaristKitTests/AquaristKitTests.swift`:
  2 new unit tests in suite `Tank workspace layout — region mapping and continuity`
  verifying single-pane region mapping and bidirectional fold-simulation continuity
  persistence, plus JSON encoding/decoding round-trip.
- `App/TankWorkspaceLayout.swift`: the single workspace seam view. Resolves
  today to the existing single-pane `TankWallView` on iPhone, mapping path changes
  into workspace selection state.
- `App/AquaristApp.swift`: updated root scene to present `TankWorkspaceLayout(model:)`.
- `App/TankWallView.swift`:
  - Uses `NavigationStack(path:)` with `NavigationLink(value:)` and `.navigationDestination(for: UUID.self)`.
  - Cards are marked `.accessibilityAddTraits(.isHeader)` for VoiceOver rotor navigation,
    with explicit `.accessibilityLabel`, `.accessibilityValue`, and `.accessibilityHint`.
  - Wall scroll position is bound via `.scrollPosition(id:)` to `workspace.continuity.wallScrollAnchorTankID`.
  - Status badges use primary text against the semantic card background with a
    colored stroke border, replacing low-contrast tint-on-tint styling.
- `App/QuickLogView.swift`:
  - Added `@AccessibilityFocusState` with `initialAccessibilityFocus` directing
    VoiceOver focus to the first actionable control on sheet presentation.
  - Added explicit accessibility hints and >=44pt touch targets on Save and Cancel buttons.
- `Scripts/check_status_contrast.py` & `Scripts/tests/test_status_contrast.py`:
  deterministic WCAG-AA contrast ratio checker for light and dark status token pairs
  (light 18.82:1, dark 17.01:1, both far exceeding the 4.5:1 minimum), plus a
  source guard that fails if the SwiftUI status-band color tokens drift.
- `Scripts/ci.sh`: integrated `status_contrast_guard` step into CI validation.
- `docs/dual-screen.md`: documents unfolded design target, control-surface + ledger
  dual-pane layout, test-day capture flow, selection/scroll continuity, and the
  migration checklist for future native dual-screen APIs.
- `UITests/AquaristLaunchTests.swift`:
  - `testQuickLogInitialControlsFollowLogicalOrderAndToolbarActionsAreHittable`:
    verifies top-to-bottom ordering of the always-visible quick-log inputs plus
    hittable Cancel/Save toolbar actions, without depending on lazily unrealized
    Form rows or toolbar-label AX frame dimensions.
  - `testWallAndQuickLogRenderAtAccessibilityDynamicType`: asserts card rendering
    under AX5 Dynamic Type and attaches screenshots (`AX5-Tank-Wall`, `AX5-Water-Change-Quick-Log`)
    to the test result bundle.

## Accessibility choices made in this pass

- Status bands: text uses `.primary` on `secondarySystemGroupedBackground` (Capsule)
  with a colored stroke outline. In light mode: contrast is 18.82:1; in dark mode: 17.01:1.
  Both well exceed WCAG AA 4.5:1 and WCAG AAA 7:1.
- Wall cards: each card provides a complete VoiceOver summary (status, volume, kind,
  key ages) and has the `.isHeader` trait to allow rotor navigation by headings.
- Quick-log sheets: `@AccessibilityFocusState` establishes immediate focus on the
  first interactive control (e.g. segmented picker or text field) when opened.
- Interactive tap targets: Cancel and Save have explicit `minWidth: 44, minHeight: 44`.

## Verification actually performed (Linux executor, 2026-09-28, no Xcode/simulator on host)

- `swift test --package-path Packages/AquaristKit` inside `swift:6.2-noble`:
  **30 tests in 10 suites passed** (including the 2 new `Tank workspace layout` tests).
- `swift test --package-path Packages/AquaristStore` in `swift:6.2-noble` (with `libsqlite3-dev`):
  **18 tests in 4 suites passed**.
- `python3 -m unittest discover -s Scripts/tests`: **24 tests passed** (including
  the 3 new status contrast/token-drift tests).
- `python3 Scripts/check_status_contrast.py`: PASS (guarded SwiftUI tokens present;
  light 18.82:1, dark 17.01:1).
- `bash scripts/check_zero_network.sh`: PASS (empty allowlist, no networking found).
- `swiftc -parse` on all changed and added Swift files under `App/` and `UITests/`: clean syntax parse.
- pbxproj object-ID closure probe: 46 defined, 0 missing refs.
- iPhone-only pre-build grep: `TARGETED_DEVICE_FAMILY = 1;` count = 4, no iPad entries.
- `git diff --check`: clean (no trailing whitespace or conflict markers).

## CI-pending claims (NOT claimed from this host)

- The actual Xcode build of `Aquarist.app`, the XCUITest run of `AquaristLaunchTests`
  (including dynamic type screenshot capture and element frame assertions), the
  post-build `UIDeviceFamily == [1]` assertion, and pixel-level screenshot inspection
  are **CI-pending**: authoritative evidence is the macOS CI run on GitHub Actions.
- No physical-device or TestFlight evidence is claimed (issue #7 owns release).
