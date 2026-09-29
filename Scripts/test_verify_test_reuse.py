import unittest
from verify_test_reuse import validate_diff

BEFORE = 'CFBundleShortVersionString: "0.5.1"\nCFBundleVersion: "6"\nSWIFT_VERSION: "5.0"'
AFTER = 'CFBundleShortVersionString: "$(MARKETING_VERSION)"\nCFBundleVersion: "$(CURRENT_PROJECT_VERSION)"\nSWIFT_VERSION: "5.0"'


class ReuseTests(unittest.TestCase):
    def test_version_repair_allowed(self):
        validate_diff(["project.yml"], BEFORE, AFTER)

    def test_changed_app_or_test_not_allowed(self):
        for path in ["Sources/LiveCue/AppModel.swift", "UITests/LiveCueUITests.swift", "Package.resolved", "Scripts/boot_simulator.py"]:
            with self.assertRaises(ValueError):
                validate_diff(["project.yml", path], BEFORE, AFTER)

    def test_other_project_changes_not_allowed(self):
        with self.assertRaises(ValueError):
            validate_diff(["project.yml"], BEFORE, AFTER.replace('"5.0"', '"6.0"'))

    def test_duplicate_or_malformed_version_not_allowed(self):
        for after in [AFTER + '\nCFBundleVersion: "8"', AFTER.replace('"$(CURRENT_PROJECT_VERSION)"', 'anything')]:
            with self.assertRaises(ValueError):
                validate_diff(["project.yml"], BEFORE, after)


if __name__ == "__main__":
    unittest.main()
