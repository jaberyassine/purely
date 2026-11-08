# Purely — DevOps delivery project

Purely is a React and Spring Boot application used to demonstrate tested delivery,
versioned container releases, GitOps reconciliation, health checks, monitoring,
and recovery. This is a preparation branch, not a verified production deployment.

Current status: local validation, 47 Maven tests, ten application image builds/scans, and all 34 configured Docker runtime/business checks pass. The integration covers real temporary MongoDB, HTTPS, signup/sign-in, catalog, cart, checkout and ownership restrictions. See [verified results](docs/VALIDATION.md) and [before/after evidence](docs/SECURITY-RESULTS.md). GitHub/Sonar execution and the Azure release/deployment remain to be verified.

## Delivery path

1. Pull requests run Java tests, the React build, configuration checks, Helm validation,
   and Terraform validation.
2. The manually started release workflow repeats validation, waits for Sonar quality
   gates, builds commit-tagged images, and blocks HIGH/CRITICAL image findings.
3. Azure login uses GitHub OIDC; scanned images are pushed to ACR.
4. A pull request updates all Helm image references to the exact source commit.
5. After review and merge, Argo CD reconciles the desired state.
6. A revert of the release merge restores the preceding image references.

The existing stack is retained: GitHub Actions, Docker, Terraform, AKS, ACR,
Helm, Argo CD, Sonar, Trivy, Prometheus, and Grafana.

## Read first

- [Changes and limitations](docs/CHANGES.md)
- [Preparation and deployment prerequisites](docs/PREDEPLOY.md)
- [Operations and interview demo](docs/RUNBOOK.md)
- [Local runtime smoke test](docs/RUNTIME-TEST.md)
- Run `./scripts/Validate-Local.ps1` from PowerShell for local checks.

## Layout

| Directory | Purpose |
| --- | --- |
| `infra` | Existing Terraform modules with preparation changes |
| `microservice-backend` | Nine Java services |
| `frontend` | React build and existing NGINX runtime |
| `k8s/charts` | Workload Helm charts |
| `k8s/argocd` | Argo CD Applications and application project |
| `k8s/observability` | Versioned dashboard and alert rules |
| `.github/workflows` | Validation and explicit release workflows |

## Important boundaries

No Terraform state, credentials, TLS key, or production data is included.
The original Desktop directories were not edited. No Azure resource was started,
created, or changed by preparation. This branch proposes the tested microservice
delivery path; it does not deploy by being pushed. Previously committed credentials
must be rotated; this change does not erase repository history.

The legacy `monolithic-backend` directory is preserved separately and is not built,
scanned or deployed by this microservice pipeline. Its runtime credentials are
externalized, but the local verification claims above do not cover that legacy app.

GitOps tracks the repository default branch (`HEAD`). The release workflow checks
that it runs on that default branch and targets its PR there. Protect that branch.
Application images start as `unreleased`; the release workflow replaces this with
the full source commit. Do not bootstrap application workloads before this happens.
