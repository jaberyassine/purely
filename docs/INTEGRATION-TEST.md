# Local business integration test

Verified host run `240d9dca9fff` passed all 34 runtime/integration checks after
47 Maven tests, all ten application image builds/scans and the MongoDB fixture
scan passed. This includes checkout, persisted cart/order state, negative access
and ownership checks and owner cancellation. See [saved results](RUNTIME-RESULTS.csv).
The following command is for reproducing the run after changes; an unchanged
passing source does not need another run.

Run in normal PowerShell with Docker Desktop running:

```powershell
& "C:\Users\jbery\Documents\Codex\2026-11-07\new-chat-3\purely-ready\scripts\Test-Integration.ps1"
```

The entry point first runs configuration/build/tests, rebuilds all ten application
images, and scans them. It then runs the existing TLS smoke test and adds real
database/business checks. A failure stops progress; no checks are skipped to make
the result green. The verified run above completed successfully.

Allow about 8 GiB or more of Docker memory for ten temporary containers (eight
Java services, frontend and MongoDB), plus room for builds on the host. Internet
is needed for dependency downloads, image pulls and the scanner database. The
first run can take longer than the smoke test.

The source includes a direct JSON access-denied handler. Earlier host run `f72688ba493e`
passed catalog/authentication and user/empty-cart reads, but a denied admin request
was redispatched to `/error` and became HTTP 401. The security chains now write
403 JSON without sendError; roles and protected routes remain enforced. Three
Spring Boot MockMvc tests passed (anonymous 401, ordinary user JSON 403 and admin
200), and the previous configuration fails the same denial-response test.
Auth/business clients are mocked in those focused tests; the subsequent passing
Docker run also verifies ordinary-user denial through the real application path.
See [authorization evidence](AUTHORIZATION-RESULTS.csv).

The earlier host run
`df021bae640c` returned correct product/category lists but failed their
cross-service lookup. A local SpringDecoder reproduction reported
`Cannot construct instance of ApiResponseDto (no Creators...)`.
Explicit no-argument/all-argument constructors preserve Lombok builders while
allowing JSON reads. The product service's partial CategoryDto ignores category
description/image fields that it does not consume. Maven's parameter metadata
also exposed ambiguity between Java `isSuccess` and JSON `success`; all seven
envelopes now explicitly map their JSON creator to `success`, `message`, and
`response`. The `success` wire name is unchanged. Six test classes cover all 13
declared Feign response signatures, nested cart items, three request bodies and
six compiler-metadata/boolean-wire checks: 22 JUnit cases passed with
`-parameters -g --release 21`, matching Maven's compiler settings. Tests fail if
parameter metadata is absent, so a plain javac run cannot hide this mismatch again.
All seven services' DTO source sets compile. These decoder checks use cached dependencies
and synthetic HTTP responses; they do not replace the Docker integration run.
See [test counts](FEIGN-CONTRACT-RESULTS.csv).

## Isolation and data

- A uniquely named user-defined bridge contains the application containers.
  Published application ports bind explicitly to 127.0.0.1; MongoDB has no published
  port. This network does not block outbound traffic. All database URIs point to
  the disposable MongoDB; no production credentials or SMTP service are supplied.
  The earlier `--internal` mode did not publish the loopback registry port on the
  tested Docker Desktop host, so host-side readiness checks could not connect.
- A local test image based on `mongo:8.0.34` is built with refreshed apt packages
  and without the unused Docker root entrypoint, gosu, js-yaml, mongos or database
  dump/import tools. The test starts mongod directly as UID 999 and seeds through
  mongosh; it does not use those removed utilities. The Dockerfile is
  `scripts/test-mongo/Dockerfile`, with a context restricted to that file.
  The derived image is resolved to its local image ID and scanned for
  HIGH/CRITICAL vulnerabilities and secrets before starting. Findings block the
  test. The scan report and exact image ID are retained. This does not certify the
  database image for production. Its upstream source is the
  [Docker Official Image definition](https://github.com/docker-library/mongo/blob/master/8.0/Dockerfile).
- MongoDB runs as UID/GID 999, with authentication, no published database port,
  read-only root and tmpfs data. It uses no host database directory or named volume.
- Random temporary database/JWT/password values are generated for this run.
  Each service gets a database-scoped account; user-service has read-only access
  to the identity database shared with auth-service, matching the current data model.
- Synthetic fixtures contain one category, one product priced at 25 and two newly
  registered users. No Atlas credentials, production data, SMTP or Azure are used.
- API requests travel through frontend HTTPS, NGINX, gateway and service discovery.
  TLS certificate, hostname and revocation checks remain enabled.
- Tokens are passed to curl in temporary header files, not command-line arguments.
  Request/header files and sign-in responses are removed after each request;
  database environment files are removed when the integration function exits.
- The outer runtime script collects container logs and removes only container and
  network IDs created by this run. MongoDB data disappears with its container.
  If PowerShell is forcibly terminated, automatic cleanup cannot be guaranteed;
  inspect that run's resources and ignored `.validation/runtime/<run-id>` directory.

## Assertions

1. Product/category fixtures match database values, including a cross-service
   product-by-category lookup.
2. Public registration and password sign-in return a real JWT. Requesting `admin`
   during public signup still grants only `ROLE_USER`.
3. Wrong password and anonymous cart access return 401; a user attempting an admin
   category write receives 403.
4. The user service reads the new identity. Adding a product persists a cart with
   quantity 1 and subtotal 25.
5. Another signed-in user cannot read or clear that cart (404).
6. Checkout creates a persisted PENDING order for 25 and clears the cart.
7. Another user cannot cancel the order (404); its owner can cancel it and the
   CANCELLED status is persisted.

Successful API responses must contain the boolean JSON field `success: true`;
the Java `isSuccess()` getter is serialized with that wire name. A missing/false
success flag or malformed JSON fails immediately instead of being retried as a
discovery delay. TLS certificate errors also fail immediately.

Only read/discovery checks are retried. Registration and checkout are sent once
to avoid hiding duplicate-write behavior. The test does not cover payment, email,
browser JavaScript, every authorization path, AKS networking, monitoring ingestion,
Argo CD reconciliation, load or recovery. These assertions are not a full security audit.

Results append to `.validation/runtime/<run-id>/runtime-results.csv`; the latest
report is `.validation/runtime-results.csv`. The saved current run is `240d9dca9fff`.

After a successful `Validate-SecurityUpgrade.ps1` run, a runtime-only retry is:

```powershell
& "C:\Users\jbery\Documents\Codex\2026-11-07\new-chat-3\purely-ready\scripts\Test-Runtime.ps1" -IncludeIntegration
```

Use that retry only when application source/images have not changed since the
successful build/scan. It still verifies each application image ID against the
passing scan summary and scans the temporary MongoDB image before starting it.

The MongoDB fixture build is deliberately uncached so apt updates are refreshed.
The application images are reused on a runtime-only retry; no Azure build or
deployment is involved. The derived image build/scan and the complete configured
business flow passed in host run `240d9dca9fff`.

### MongoDB scan baseline

Host run `e287cb647eff` passed all 14 core smoke checks, then correctly blocked
the unmodified upstream MongoDB image: 38 HIGH findings and one CRITICAL finding,
with zero HIGH/CRITICAL secrets. The affected targets were apt/libapt (2), js-yaml
(3), eight Go database-tool binaries (8) and gosu's Go runtime (26). These are
per-target findings, not 39 distinct CVEs. The local fixture Dockerfile addresses
this observed scope; the subsequent derived-image Trivy scan passes. No
ignore list, severity reduction or scanner exclusion was added.

The derived fixture image passed again in run `240d9dca9fff`: zero HIGH,
zero CRITICAL and zero HIGH/CRITICAL secrets. See [scan evidence](MONGO-SCAN-RESULTS.csv)
for the image ID and timestamp. MongoDB fixture initialization, readiness of
all six database-backed services and all configured business assertions passed.
The success assertion matches the actual JSON `success` wire name and rejects
bad contracts without waiting for a discovery timeout.

## Application fixes accompanying this test

Public signup now assigns the user role on the server. Cart lookup/clear and order
cancellation queries include the authenticated user ID; foreign and missing IDs
return the same 404. Order authentication/creation no longer prints credentials.
Eight new JUnit cases cover role escalation, foreign cart read/clear and foreign
order cancellation, together with owner success paths. The full Maven build,
fresh image/security scan and Docker integration passed with these changes.
