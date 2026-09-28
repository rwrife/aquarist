"""WCAG contrast guard for status-band text colors.

This script keeps the accessibility audit reproducible in CI without claiming any
render-time simulator output on Linux hosts. It validates the design token pairs
used by the wall status band in both light and dark appearance targets.
"""

from __future__ import annotations

from pathlib import Path

# Guardrail against style-token drift: these snippets must stay present in
# TankWallView's status-band styling so the measured contrast pairs remain tied
# to the actual UI tokens.
REQUIRED_SWIFTUI_SNIPPETS = [
    ".foregroundStyle(.primary)",
    ".background(Color(.secondarySystemGroupedBackground), in: Capsule())",
]

# Text color + background color pairs for status-band labels.
# These map to the semantic colors explicitly required above:
# - `.primary` resolves to `label` (black in light, white in dark)
# - `secondarySystemGroupedBackground` resolves to the listed hex values
#   for the default light/dark appearances on iOS.
STATUS_TEXT_PAIRS: list[tuple[str, str, str]] = [
    ("light", "#000000", "#F2F2F7"),
    ("dark", "#FFFFFF", "#1C1C1E"),
]


def verify_status_band_uses_guarded_tokens() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    wall_file = repo_root / "App" / "TankWallView.swift"
    source = wall_file.read_text(encoding="utf-8")

    missing = [snippet for snippet in REQUIRED_SWIFTUI_SNIPPETS if snippet not in source]
    if missing:
        raise SystemExit(
            "FAIL: status-band style token drift detected in App/TankWallView.swift. "
            f"Missing required snippets: {missing}"
        )

    print("PASS: status-band SwiftUI tokens match contrast guard assumptions.")


def _hex_to_srgb_components(hex_color: str) -> tuple[float, float, float]:
    value = hex_color.strip().lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Expected 6-digit hex color, got: {hex_color!r}")
    r = int(value[0:2], 16) / 255.0
    g = int(value[2:4], 16) / 255.0
    b = int(value[4:6], 16) / 255.0
    return r, g, b


def _linearize_channel(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(hex_color: str) -> float:
    r, g, b = _hex_to_srgb_components(hex_color)
    lr = _linearize_channel(r)
    lg = _linearize_channel(g)
    lb = _linearize_channel(b)
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb


def contrast_ratio(foreground_hex: str, background_hex: str) -> float:
    l1 = relative_luminance(foreground_hex)
    l2 = relative_luminance(background_hex)
    brighter = max(l1, l2)
    darker = min(l1, l2)
    return (brighter + 0.05) / (darker + 0.05)


def run_guard() -> None:
    verify_status_band_uses_guarded_tokens()
    print("Status-band text contrast report")
    print("--------------------------------")
    for appearance, foreground, background in STATUS_TEXT_PAIRS:
        ratio = contrast_ratio(foreground, background)
        print(
            f"{appearance}: foreground={foreground} background={background} "
            f"contrast={ratio:.2f}:1"
        )
        if ratio < 4.5:
            raise SystemExit(
                f"FAIL: {appearance} status text contrast {ratio:.2f}:1 is below WCAG AA 4.5:1"
            )
    print("PASS: all status text/background pairs meet WCAG AA (>= 4.5:1).")


if __name__ == "__main__":
    run_guard()
