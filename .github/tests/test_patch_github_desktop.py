import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    'github_desktop_oauth', Path(__file__).parents[1] / 'tools/patch_github_desktop.py'
)
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


class OAuthPatchTests(unittest.TestCase):
    def test_legacy_windows_handler_gets_linux_support(self):
        source = PATCH.AUTH_BEFORE + '\n' + PATCH.WINDOWS_ONLY + ' { handle() }\n'
        result = PATCH.patch_oauth(source)
        self.assertIn(PATCH.AUTH_AFTER, result)
        self.assertIn(PATCH.LEGACY_LINUX, result)
        self.assertEqual(PATCH.patch_oauth(result), result)

    def test_native_linux_handler_is_preserved(self):
        handler = """const isLinuxProtocolLaunch =
  __LINUX__ && argv.some(matchesProtocol)
if (isWindowsProtocolLaunch || isLinuxProtocolLaunch) { handle() }
"""
        result = PATCH.patch_oauth(PATCH.AUTH_BEFORE + '\n' + handler)
        self.assertTrue(result.endswith(handler))
        self.assertNotIn(PATCH.LEGACY_LINUX, result)
        self.assertEqual(PATCH.patch_oauth(result), result)

    def test_unrecognized_protocol_registration_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'registration'):
            PATCH.patch_oauth(PATCH.WINDOWS_ONLY)

    def test_unrecognized_handler_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'handler'):
            PATCH.patch_oauth(PATCH.AUTH_BEFORE)
