# Dual-screen workspace seam (`TankWorkspaceLayout`)

This document defines Aquarist's dual-screen design target as a **pure layout seam**.
It does not use or assume any unavailable fold/hinge SDK API.

## Current shipped behavior (today)

- Runtime mode: `singlePane`
- UI container: `TankWorkspaceLayout` in `App/TankWorkspaceLayout.swift`
- Rendered surface: the existing `NavigationStack` tank wall → tank detail flow
- Supported devices: iPhone-only (`TARGETED_DEVICE_FAMILY = 1`)

## Mode vocabulary

Defined in `AquaristKit` so it is testable without app-runtime dependencies:

- `TankWorkspaceMode.singlePane`
- `TankWorkspaceMode.unfoldedTwoPaneTarget`
- `TankWorkspaceRegion.wallControlSurface`
- `TankWorkspaceRegion.detailLedger`

### Region mapping contract

| Mode | Visible regions | Behavior |
|---|---|---|
| `singlePane` + no selection | `[wallControlSurface]` | Tank wall is visible in the navigation root. |
| `singlePane` + selected tank | `[detailLedger]` | Detail view is visible for the selected tank. |
| `unfoldedTwoPaneTarget` | `[wallControlSurface, detailLedger]` | Design target: persistent wall beside selected-tank ledger/charts. |

## Selection + scroll continuity contract

`TankWorkspaceLayoutState` carries continuity fields that must survive mode transitions:

- `selectedTankID`
- `wallScrollAnchorTankID`
- `detailScrollAnchorEventID`

### Fold-simulation persistence rule

Transitioning between `singlePane` and `unfoldedTwoPaneTarget` must preserve continuity values.
No transition may clear selection or scroll anchors by side effect.

Validated by `AquaristKit` unit tests in
`TankWorkspaceLayoutTests` (`Packages/AquaristKit/Tests/AquaristKitTests.swift`).

## Unfolded target UX (design, not runtime dependency)

When native dual-screen APIs exist, Aquarist should present:

1. **Wall control surface pane (left/primary)**
   - Persistent tank wall cards
   - Quick selection without hiding the wall
   - Wall scroll position retained while detail updates

2. **Detail ledger pane (right/secondary)**
   - Selected tank detail
   - Chronological ledger and trend charts
   - Quick-log sheet entry points and inline context

3. **Test-day two-pane capture flow**
   - Keep the wall visible as a stable control surface
   - Enter test values/doses while keeping the selected-tank ledger visible
   - Preserve selection and both pane scroll positions when posture changes

## Migration checklist for future native dual-screen APIs

When Apple provides native dual-screen/fold posture APIs:

1. Keep `TankWorkspaceMode`/`TankWorkspaceRegion` semantics stable.
2. Implement posture-to-mode mapping **inside `TankWorkspaceLayout` only**.
3. Keep `TankWorkspaceLayoutState` as the continuity source of truth.
4. Preserve `selectedTankID`, `wallScrollAnchorTankID`, and `detailScrollAnchorEventID` across posture changes.
5. Add app-level UI tests that prove no continuity regression between posture changes.
6. Keep domain/store layers unchanged (`AquaristKit`, `AquaristStore` must remain fold-agnostic).
7. Do not introduce third-party dual-screen abstraction dependencies.

## Explicit non-goals

- No fold API calls in current shipping code.
- No device-posture heuristics in domain logic.
- No behavior that changes chemistry/safety wording or adds verdict logic.

## Accessibility evidence expectations for this seam

Accessibility evidence should accompany PRs that touch workspace layout:

- VoiceOver-meaningful wall navigation (card headings + concise summaries)
- Logical top-to-bottom focus order in quick-log sheets
- Status-band contrast guard output (WCAG AA for label text)
- Dynamic Type screenshots captured in XCUITest attachments

These requirements are verified through code/tests and CI artifacts; Linux runs do
not claim simulator rendering results.
