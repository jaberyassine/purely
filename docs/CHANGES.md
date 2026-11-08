# Preparation changes

## Application and containers

- Removed embedded database URIs; credentials are read from environment variables.
- Added explicit auth JWT and SMTP configuration without production defaults.
- Gave service instances distinct Eureka IDs for replica operation.
- Added startup, readiness, and liveness endpoints; Mongo-dependent services include
  Mongo in readiness, but not liveness, to avoid restart storms during database outages.
- Allowed internal health probes through existing Spring Security configuration.
- Added graceful shutdown, CPU/memory settings, non-root runtime users,
  read-only roots, dropped capabilities, and writable temporary volumes.
- Changed the frontend to same-origin API requests; removed the fixed public HTTP IP.
- Updated the frontend build runtime from Node 18 to Node 22 for Vite compatibility.
- Made JWT validation reject invalid signatures as a normal validation failure.
- Added product failure-path tests and JWT validity, expiry, and tampering tests.
- Aligned JUnit and Surefire test versions. Preloaded the existing Byte Buddy test
  agent at JVM startup to avoid dynamic attachment on Java 21; runtime images do
  not use this test instrumentation.
- Isolated auth context tests from the live role database using a mocked repository.

## Kubernetes and GitOps

- Added rolling-update settings, spreading preferences, and disruption budgets for
  the two replicated backend services. Single-replica services remain a limitation.
- Removed chart-generated database secrets; bootstrap requires external credentials.
- Added a restricted Argo CD project for application workloads.
- Replaced mutable `latest` deployment references with a release mechanism using Git SHAs.
- Replaced the duplicate ingress resources with the existing frontend NGINX serving
  TLS and proxying API requests to the internal gateway. It uses the existing
  Terraform cluster DNS address `10.1.0.10`; change both together if the network changes.
- Removed the retired ingress-nginx controller Application from this preparation.
- Consolidated desired monitoring into kube-prometheus-stack; enabled CRD management
  and consistent ServiceMonitor discovery labels across namespaces.
- Added a versioned Grafana dashboard and alerts. Alert delivery to an external
  receiver is not configured; no notification is sent by this project preparation.

## Security scan preparation

- Added `Scan-Images.ps1` to scan locally built image archives with versioned Trivy,
  without mounting the Docker socket or user credentials into the scanner.
- The report identifies HIGH/CRITICAL vulnerabilities and secret findings separately
  from scanner execution errors. Findings block release; they are not suppressed.
- Pinned the GitHub Trivy action to the safe commit published by Aqua Security and
  set the scanner version explicitly. Scoped SONAR_TOKEN to the steps that need it.
- Vendor reference: https://www.aquasec.com/blog/trivy-supply-chain-attack-what-you-need-to-know/

## Terraform changes

- Integrated the existing modules under `infra`, retaining resource addresses and
  AzureRM 3.x constraint/lock to avoid an unreviewed provider-major migration.
- Removed service-principal password arguments from the provider.
- Disabled ACR admin credentials and added AcrPull for the AKS kubelet identity.
- Parameterized the SSH public key, node sizing, and API authorized CIDRs.
- Proposed two Standard_D2s_v5 nodes instead of one B2ms node. This changes cost and
  may require node-pool rotation. A real plan must be reviewed before any apply.
- Restored protection against deleting a resource group containing resources.
- Included a remote-backend example, deliberately not activated. Existing state must
  be located and backed up before initializing the authoritative deployment workspace.

## Limits of this change

This is not a full application security audit. Existing business authorization,
database ownership checks, dependencies, Mongo backups, certificate renewal,
cluster upgrades, and disaster recovery still require review. Image scans and
Sonar gates may correctly block the first release until their findings are fixed.
No local configuration validation proves live uptime, TLS trust, Azure RBAC,
monitoring ingestion, or recovery time. Those require subsequent runtime tests.

Official reference for ingress-nginx retirement:
https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
