Purely previously skipped tests, allowed quality/security checks to fail, and
published mutable image tags without updating GitOps desired state. This change
enforces release gates, builds commit-tagged images, and proposes Helm version
updates through a reviewed pull request for Argo CD to reconcile.

It also updates the backend to Boot 4.1.2 / Cloud 2025.1.4, removes embedded runtime
credentials, hardens containers, adds probes and monitoring, and replaces the
duplicate ingress setup with the existing frontend NGINX serving TLS.

Validation: 25 local checks, 47 Maven tests, ten image builds/scans, and all 34
Docker runtime/business checks passed. Current scans contain no HIGH/CRITICAL
vulnerability or secret findings. See docs/VALIDATION.md and docs/SECURITY-RESULTS.md
for scope, image IDs and scan times. GitHub/Sonar,
OIDC/ACR, real Terraform plan, and AKS runtime behavior still require verification.
No Azure resources were changed during preparation.
