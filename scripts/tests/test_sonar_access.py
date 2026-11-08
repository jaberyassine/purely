import contextlib
import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import URLError

spec = importlib.util.spec_from_file_location("sonar_access", Path(__file__).parents[1] / "sonar-access.py")
sonar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sonar)


class SonarAccessTests(unittest.TestCase):
    def run_case(self, token, result=None, error=None):
        output = io.StringIO()
        with patch.dict(os.environ, {"SONAR_TOKEN": token}, clear=True), patch.object(
            sonar, "request_auth", return_value=result, side_effect=error
        ) as request, contextlib.redirect_stdout(output):
            code = sonar.main()
        if token:
            self.assertNotIn(token, output.getvalue())
        return code, request, output.getvalue()

    def test_missing_or_malformed_tokens_never_reach_network(self):
        for token in ("", " fixture-only", "fixture-only\n", '"fixture-only"', "Bearer fixture-only"):
            with self.subTest(token_kind="malformed" if token else "missing"):
                code, request, _ = self.run_case(token)
                self.assertEqual(code, 1)
                request.assert_not_called()

    def test_http_failure_and_false_validation_block_release(self):
        for result in ((403, False), (401, False), (200, False), (302, False)):
            code, _, _ = self.run_case("fixture-only-token", result=result)
            self.assertEqual(code, 1)

    def test_network_errors_are_sanitized(self):
        code, _, output = self.run_case("fixture-only-token", error=URLError("fixture-only-token"))
        self.assertEqual(code, 1)
        self.assertIn("could not reach", output)

    def test_authenticated_token_can_proceed(self):
        code, request, output = self.run_case("fixture-only-token", result=(200, True))
        self.assertEqual(code, 0)
        request.assert_called_once_with("fixture-only-token")
        self.assertIn("valid=true", output)

    def test_redirects_are_not_followed(self):
        self.assertIsNone(sonar.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.invalid"))


if __name__ == "__main__":
    unittest.main()
