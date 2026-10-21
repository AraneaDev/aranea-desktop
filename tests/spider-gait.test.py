"""A stance must push backwards at constant speed, with smooth grounded contacts."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/spider"))
from gait import toe_motion, DUTY, STRIDE


class GaitTests(unittest.TestCase):
    def test_stance_pushes_backwards_at_constant_speed(self):
        samples = [toe_motion(p * DUTY / 10) for p in range(11)]
        for a, b in zip(samples, samples[1:]):
            self.assertAlmostEqual(b[0] - a[0], -STRIDE / 10)
            self.assertAlmostEqual(a[1], 0)
        self.assertAlmostEqual(samples[-1][1], 0)

    def test_swing_recovers_forward_with_soft_ground_contacts(self):
        self.assertGreater(
            toe_motion(DUTY + (1 - DUTY) * 0.75)[0],
            toe_motion(DUTY + (1 - DUTY) * 0.25)[0],
        )
        self.assertGreater(toe_motion(DUTY + (1 - DUTY) * 0.5)[1], 0.1)
        eps = 1e-5
        for phase in [0, DUTY, 1]:
            a, b = toe_motion(phase - eps), toe_motion(phase + eps)
            self.assertLess(abs(a[0] - b[0]), 1e-4)
            self.assertLess(abs(a[1] - b[1]), 1e-6)
        self.assertEqual(toe_motion(0), toe_motion(1))

    def test_world_foot_stays_planted_with_matching_root_speed(self):
        scale = 0.65
        duration = 2
        root_speed = scale * STRIDE / (DUTY * duration)
        values = [
            root_speed * (phase * duration) + scale * toe_motion(phase)[0]
            for phase in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        ]
        self.assertLess(max(values) - min(values), 1e-8)


if __name__ == "__main__":
    unittest.main()
