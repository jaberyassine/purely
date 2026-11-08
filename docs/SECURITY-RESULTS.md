# Image security results - 7 November 2026

All ten rebuilt images passed the configured HIGH/CRITICAL vulnerability and secret policy using Trivy 0.76.2. The backend reports include both Ubuntu packages and Java libraries; the frontend report covers Alpine. This is a result for these image IDs and this database snapshot, not a claim that all vulnerabilities are absent.

| Image | Before HIGH | Before CRITICAL | After HIGH | After CRITICAL | After HIGH/CRITICAL secrets |
| --- | ---: | ---: | ---: | ---: | ---: |
| product-service | 52 | 13 | 0 | 0 | 0 |
| auth-service | 52 | 13 | 0 | 0 | 0 |
| api-gateway | 49 | 4 | 0 | 0 | 0 |
| cart-service | 52 | 13 | 0 | 0 | 0 |
| category-service | 52 | 13 | 0 | 0 | 0 |
| notification-service | 47 | 11 | 0 | 0 | 0 |
| order-service | 52 | 13 | 0 | 0 | 0 |
| service-registry | 47 | 12 | 0 | 0 | 0 |
| user-service | 47 | 13 | 0 | 0 | 0 |
| frontend | 0 | 0 | 0 | 0 | 0 |

Counts are findings per image, not distinct CVEs across the project. [CSV evidence](SECURITY-RESULTS.csv) records exact image IDs and scan times. Raw reports and the baseline remain in `.validation/trivy/reports` and `.validation/trivy/baseline`.

Remediation: aligned Boot 4.1.2 / Cloud 2025.1.4 dependencies, targeted legacy transitive updates, and Ubuntu apt package updates. The gate was retained.
