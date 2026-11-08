# Verified local preparation - 7 November 2026

Host run `240d9dca9fff` passed all 34 runtime/integration checks after a full
successful build, test and image scan. No application source changes followed
that passing run. The script completed its cleanup/report stage without a
reported container/network cleanup failure. Temporary database environment,
request, bearer-header and sign-in response files were checked and are absent.
The temporary CA files remain only in the ignored local validation directory.

| Check | Verified result |
| --- | --- |
| Configuration / Helm / Terraform / application validation | 25 checks passed |
| Java builds | Nine services pass Maven verify on Boot 4.1.2 / Cloud 2025.1.4 |
| Java unit/context/security/contract tests | 47 tests; zero failures; zero errors |
| React production build | PASS |
| Helm | Ten workload charts and the observability chart pass |
| Terraform | Formatting, init without backend, and validate pass |
| Docker | Engine check and ten local application image builds pass |
| Trivy application-image policy | Ten images: zero HIGH, CRITICAL and HIGH/CRITICAL secret findings |
| Temporary MongoDB fixture policy | Zero HIGH, CRITICAL and HIGH/CRITICAL secret findings |
| Runtime and business integration | 34 checks passed; run `240d9dca9fff` |

The container run verifies readiness and metrics endpoints, trusted local HTTPS
with revocation checks, blocked public actuator access, proxy routing and Eureka.
It also verifies real MongoDB-backed catalog/category lookup, public signup and
password sign-in/JWT, rejection of invalid/anonymous/admin-only access, adding a
product to a cart (quantity 1, subtotal 25), persisted checkout and cart clearing.
A second user cannot read/clear the first user's cart or cancel its order; the
owner can cancel and the CANCELLED status is persisted. Public signup cannot
self-assign the admin role.

Evidence: [runtime results and exact tested image IDs](RUNTIME-RESULTS.csv),
[application image scan evidence](SECURITY-RESULTS.csv),
[MongoDB fixture scan](MONGO-SCAN-RESULTS.csv),
[Feign contract checks](FEIGN-CONTRACT-RESULTS.csv), and
[focused authorization checks](AUTHORIZATION-RESULTS.csv).
The nine application image IDs exercised by the runtime test match the passing
application scan summary. Notification-service was built/scanned, but email was
not exercised. Raw local reports and Maven Surefire XML remain under `.validation`
and each service's target directory, excluded from the source ZIP.

## Scope and remaining deployment prerequisites

The result is for local Docker, temporary data, these image IDs and the scanner
database snapshots. LOW/MEDIUM findings were outside the configured gate.
It does not verify payment, SMTP, browser JavaScript, every authorization path,
load, recovery or production database connectivity.

Before AKS deployment, complete the repository integration and real GitHub
validation/release, Sonar gates, Azure OIDC/ACR push and image-version PR. Rotate
previously exposed credentials and review the authoritative Terraform state and
real saved plan. Do not use an empty state against existing Azure resources.
After deployment, verify Argo CD reconciliation, probes, AKS DNS/Service routing,
actual certificate/DNS, metrics ingestion, drift correction and recovery.
See [deployment preparation](PREDEPLOY.md) and [integration scope](INTEGRATION-TEST.md).

No Azure resources were started, provisioned or changed by these local checks.