import unittest

from Scripts.check_status_contrast import (
    STATUS_TEXT_PAIRS,
    contrast_ratio,
    verify_status_band_uses_guarded_tokens,
)


class StatusContrastTests(unittest.TestCase):
    def test_black_on_white_is_twenty_one_to_one(self):
        self.assertAlmostEqual(contrast_ratio("#000000", "#FFFFFF"), 21.0, places=2)

    def test_guarded_swiftui_tokens_present(self):
        verify_status_band_uses_guarded_tokens()

    def test_status_text_pairs_meet_wcag_aa(self):
        for appearance, foreground, background in STATUS_TEXT_PAIRS:
            with self.subTest(appearance=appearance):
                self.assertGreaterEqual(contrast_ratio(foreground, background), 4.5)


if __name__ == "__main__":
    unittest.main()
