# Issue #6 review evidence

## Implementation

- Each tank detail now includes an oldest-first append-only history with event-kind filters. Original reading, dose, livestock, equipment, note, correction, and stored reference-band text is displayed without interpretation. Quick Log preserves the original nonempty text on save.
- SwiftUI Charts displays per-parameter raw numeric records as points. Lines are separate contiguous runs, split wherever a reading is unparseable. The dated raw-value list remains visible for every reading, including text that cannot be plotted. Axis labels are Date and the user's parameter name.
- The roster derives from effective add/remove/observe events. It shows known zero after a complete removal and Unknown when the available history cannot establish a quantity. First-add and last-activity dates and observation notes are shown. Corrections remove their target from derived views while the full ledger retains both rows.

## Copy review checklist

- [x] Chart titles, axes, empty states, and point descriptions contain no safety, toxicity, diagnosis, or treatment verdicts.
- [x] Reference bands are labeled as the user's recorded text; no membership verdict is shown.
- [x] Unknown quantities and unparseable readings are identified without inferring a value.
- [x] Event notes and observation notes are displayed verbatim.

## Verification on Linux

- `swift test --package-path Packages/AquaristKit` in `swift:6.2-noble`: 32 tests passed, including roster dates, partial records, correction, zero quantity, and verbatim observation notes.
- `swift test --package-path Packages/AquaristStore` in the same container with `libsqlite3-dev`: 18 tests passed.
- `python3 -m unittest discover -s Scripts/tests -q`: 24 tests passed.
- `bash scripts/check_zero_network.sh` and `python3 Scripts/check_status_contrast.py`: passed.
- The iOS app and XCUITests require pinned Xcode 26.0.1 (17A400) on an Apple runner and have not run on Linux. No device, archive, or TestFlight result is claimed.
