"""Check the release environment token on its real runner without logging it."""

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

AUTH_URL = "https://sonarcloud.io/api/authentication/validate"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the authorization header to another destination.
        return None


def request_auth(token):
    request = Request(
        AUTH_URL,
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
    )
    try:
        with build_opener(NoRedirect()).open(request, timeout=30) as response:
            status = response.status
            try:
                body = json.loads(response.read(65536))
                valid = isinstance(body, dict) and body.get("valid") is True
            except (ValueError, UnicodeError):
                valid = False
            return status, valid
    except HTTPError as error:
        error.close()
        return error.code, False


def main():
    token = os.environ.get("SONAR_TOKEN", "")
    if not token:
        print("::error::SONAR_TOKEN is missing from the release job.")
        return 1
    if any(c.isspace() for c in token) or token[:1] in ("'", '"') or token[-1:] in ("'", '"'):
        print("::error::SONAR_TOKEN contains whitespace or quotes. Store only the raw token in the release environment secret.")
        return 1
    try:
        status, valid = request_auth(token)
    except (URLError, TimeoutError, OSError):
        print("::error::The runner could not reach the Sonar authentication endpoint over HTTPS.")
        return 1
    print(f"Sonar authentication: HTTP {status}; valid={str(valid).lower()}")
    if status != 200 or not valid:
        print("::error::The token supplied to this GitHub release job did not authenticate. Check SONAR_TOKEN in the release environment; do not print its value.")
        return 1
    print("Sonar token authenticated on this runner. Project analysis permissions and quality gates will be checked by the scanners.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
