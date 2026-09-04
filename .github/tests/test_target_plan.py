import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/target_plan.py"
SPEC = importlib.util.spec_from_file_location("target_plan", MODULE_PATH)
assert SPEC and SPEC.loader
TARGET_PLAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TARGET_PLAN)


class TargetPlanTests(unittest.TestCase):
    def test_verified_cells_expand_all_to_two_native_architectures(self):
        matrix = {
            "targets": [
                {
                    "id": "ubuntu-24.04",
                    "native_runners": {
                        "amd64": "ubuntu-24.04",
                        "arm64": "ubuntu-24.04-arm",
                    },
                }
            ],
            "packages": [
                {
                    "id": "nivora-cli",
                    "architectures": ["all"],
                    "support": [
                        {
                            "targets": ["ubuntu-24.04"],
                            "tier": "verified",
                        }
                    ],
                }
            ],
        }
        self.assertEqual(
            TARGET_PLAN.verified_cells(matrix),
            [
                {
                    "package": "nivora-cli",
                    "target": "ubuntu-24.04",
                    "architecture": "amd64",
                    "runner": "ubuntu-24.04",
                },
                {
                    "package": "nivora-cli",
                    "target": "ubuntu-24.04",
                    "architecture": "arm64",
                    "runner": "ubuntu-24.04-arm",
                },
            ],
        )

    def test_verified_cell_requires_a_native_runner(self):
        matrix = {
            "targets": [{"id": "ubuntu-24.04", "native_runners": {}}],
            "packages": [
                {
                    "id": "demo",
                    "architectures": ["amd64"],
                    "support": [
                        {
                            "targets": ["ubuntu-24.04"],
                            "tier": "verified",
                        }
                    ],
                }
            ],
        }
        with self.assertRaisesRegex(ValueError, "has no native runner"):
            TARGET_PLAN.verified_cells(matrix)


if __name__ == "__main__":
    unittest.main()
