# Local runtime smoke test

Verified on 7 November 2026: host run `240d9dca9fff`, with `-IncludeIntegration`,
passed all 34 runtime/business checks, including the core smoke checks below.
The [saved results](RUNTIME-RESULTS.csv) include the exact tested image IDs.
The report was written after cleanup with no reported cleanup failures.
See [business integration scope](INTEGRATION-TEST.md); the remainder of this
document describes the default three-container smoke mode.

Run `scripts/Test-Runtime.ps1` in normal PowerShell with Docker Desktop running.
It uses the locally built registry, API gateway, and frontend images; it does not
pull application images or access Azure, production databases, or user credentials.
It verifies each image ID against the passing local scan summary and starts that
exact image ID, rather than trusting a mutable local tag.

The script creates an isolated Docker network and three containers with the
non-root users, read-only roots, resource limits, and writable temporary mounts
used by the Kubernetes preparation. Published ports bind only to 127.0.0.1.
Docker allocates application ports; the CRL uses an available loopback port.
It creates a two-day localhost certificate with OpenSSL
and explicitly verifies it with curl; it does not disable TLS verification or
install a certificate into Windows trust stores.
The temporary CA also signs a revocation list, with a localhost HTTP distribution
point included in the certificates. A test-only NGINX location serves the public
CRL so Windows Schannel can perform its normal revocation checks. The CA private
key stays on the host; only the server key/certificate and public CRL are mounted.

Checks cover registry/gateway readiness and metrics, frontend HTTPS/static SPA
delivery and headers, actuator access blocking, proxy routing, and Eureka
registration. An expected gateway JSON 503 verifies the proxy path when the
product service is deliberately absent; it is not a successful product request.

For local execution, a copy of nginx.conf uses Docker's resolver in place of AKS
DNS and connects directly to gateway container port 8081. In AKS, the gateway
Service maps port 80 to targetPort 8081; the isolated Docker test has no Kubernetes
Service to perform that mapping. The source configuration and production image
are not modified. This adaptation does not prove AKS DNS or Service routing works.
The proxy check requests JSON and reports an unexpected HTTP status before
attempting to parse the saved response, so an NGINX error remains diagnosable.

The script removes only the exact container/network IDs it created. Logs, results,
and the temporary test certificate remain under `.validation/runtime/<run-id>`.
The latest CSV is `.validation/runtime-results.csv`. These files are excluded from
the source ZIP and Git. A failed cleanup is reported rather than silently ignored.

The default smoke test does not validate MongoDB connectivity, authentication, registration,
cart/order business operations, browser JavaScript behavior, Prometheus ingestion,
or Argo CD reconciliation. Those remain separate integration/runtime checks.

For the prepared disposable MongoDB/business checks, run `scripts/Test-Integration.ps1`.
It rebuilds and scans first, then calls this script with `-IncludeIntegration`.
See [scope and pending execution](INTEGRATION-TEST.md).
