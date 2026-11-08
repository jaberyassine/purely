# Security remediation - initial image scan

Status: remediation implemented and locally verified. All nine Java builds, 14 tests, and ten image builds passed; the rescan reports zero HIGH/CRITICAL findings in every image. No vulnerability ignore was added. See [scan evidence](SECURITY-RESULTS.md).

## Baseline

The first Trivy scan completed successfully. Nine backend images were blocked by
HIGH/CRITICAL findings; the frontend had none at those severities. No HIGH/CRITICAL
secret findings were reported. These are scanner results, not evidence of exploitation.
Many findings repeat across images because their dependencies are shared.

Original reports are preserved in `.validation/trivy/baseline`. A source checkpoint
is preserved as `.validation/pre-security-upgrade.zip`. Terraform state and private
credentials are not in that checkpoint.

## Changes prepared

| Component | Previous | Prepared change |
| --- | --- | --- |
| Spring Boot | 3.2.2 / 3.2.5 | 4.1.2 in all nine services |
| Spring Cloud | 2023.0.1 | 2025.1.4, compatible with Boot 4.1.2 |
| Spring, Security, Tomcat, Netty, Jackson, Micrometer, MongoDB library | Older versions from the original BOM | Use the aligned Boot/Cloud dependency sets |
| Guava | 19.0 | Manage 33.7.2-jre when present transitively |
| XStream | 1.4.19 | Manage 1.4.21 when present transitively |
| Commons FileUpload | 1.5 | Manage 1.6.0 when present transitively |
| Commons IO | 2.11.0 | Manage 2.20.0 when present transitively |
| Bouncy Castle | 1.77 | Align provider/PKIX/utility libraries to 1.85 |
| Ubuntu apt / libapt | 2.4.14 | Update from Ubuntu repositories during runtime image build |

Boot 4 is a major migration. The source changes include the Security authentication
provider constructor, Jackson 3 error-response serialization, replacement of MockBean
with MockitoBean, MongoDB connection configuration, the MVC/Gateway
starter names, and Gateway WebFlux property namespace. JUnit now follows Boot's BOM.
JSON compatibility defaults are enabled to reduce response-format changes.

The initial migration run compiled all services, but six context tests failed
because readiness referred to `mongodb`. Inspection of the actual Boot 4.1.2
auto-configuration confirms that it registers `mongoHealthContributor`; the readiness
group must include `mongo`. This configuration has been corrected in those six
services. Health membership validation remains enabled.

These edits do not prove business behavior is preserved. Test authentication,
registration, JSON responses, product browsing, cart/order operations, database
connections, service discovery, health endpoints, and metrics before deployment.

## Verification

The rebuilt source passed Maven verify for all nine services and all 14 unit/context tests. Terraform validation, Helm checks, and React builds passed as well. All ten rebuilt images then passed the configured Trivy HIGH/CRITICAL vulnerability and secret policy. The check did not deploy anything to Azure. See [validation](VALIDATION.md) for evidence and remaining runtime/release checks.

## Primary references

- Boot release: https://spring.io/blog/2026/10/23/spring-boot-4-1-2-available-now/
- Cloud compatibility: https://spring.io/blog/2026/10/23/spring-cloud-2025-1-4-has-been-released/
- Migration guide: https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide
- Framework fix availability: https://spring.io/security/cve-2026-47884/
- Managed versions: https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html
