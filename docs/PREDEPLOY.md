# Before AKS deployment

Local verification is complete: 47 Maven tests and all 34 configured Docker
runtime/business checks passed. Start deployment preparation with
`scripts/Get-AksPreflight.ps1` in normal PowerShell. It inventories the selected
Azure account and the expected `dev-rg` / `dev-aks` / `purelyacr` resources using
read-only show/list commands. It does not start AKS, export kubeconfig, push images
or apply Terraform. Review subscription identity, cluster power/state, node pools,
registry and the frontend's assumed DNS resolver before any later change.
Reports are saved in `.validation/aks-preflight/<timestamp>`. A readable resource
is not a deployment readiness approval. The repository is now reachable at
`https://github.com/jaberyassine/purely`, with `master` as its default branch.
The prepared source must pass its pull-request checks before review/merge.

## 1. Review and integrate the source

- Review this copy against the original source before merging into the real repository.
- Confirm the repository URL and protected release branch. The prepared files use
  `https://github.com/jaberyassine/purely.git` and its default branch (`HEAD`).
- Require review for `.github/workflows`, `infra`, and `k8s` changes.
- Run `scripts/Validate-Local.ps1` with internet access. Resolve every failed check.
- Run `scripts/Scan-Images.ps1` on the local images and review its security summary.
  Reports/cache are under `.validation/trivy`; a single exported image archive is
  reused. A passing build is not a passing security scan.
- Run the GitHub Validate workflow before starting a release.
- Run `scripts/Test-Integration.ps1` and review every result. This rebuilds/scans
  the latest source and tests real database/business flows with disposable data.

## 2. Replace exposed credentials

Rotate the database credential and any previously committed SMTP/JWT/Grafana
credentials. Removing them from the current source does not revoke them or erase
Git history. Never paste credentials into issues, workflow arguments, or Git.

Required runtime Secrets (created out of band, after the cluster is available):

| Namespace | Secret | Keys |
| --- | --- | --- |
| Each of auth, user, product, category, cart, order **with the `-service` suffix** | `mongodb-secret` | `uri` |
| `auth-service` | `auth-secret` | `jwt-secret` (base64-encoded random key of at least 32 bytes) |
| `notification-service` | `smtp-secret` | `smtp-host`, `smtp-username`, `smtp-password` |
| `monitoring` | `grafana-admin` | `admin-user`, `admin-password` |
| `frontend` | `purely-tls` | Kubernetes TLS Secret: `tls.crt`, `tls.key` |

Use appropriately scoped Mongo users/databases per service. Preserve the required
existing test/demo data. Do not introduce destructive database migrations for a demo.
Use a valid certificate covering the chosen application DNS name, include its chain,
and arrange renewal. Private keys must never be committed.

## 3. Preserve Terraform state

The existing state remains in the original Desktop Terraform directory. It was not
copied into this preparation. Do not run a plan/apply from a new empty state against
existing resources. Back up state securely and use the same authoritative state when
reviewing this source. A stopped AKS cluster is still an existing resource.

The remote backend example is inactive. Configure/migrate it only after verifying
storage access, the state identity, and a recoverable backup. Do not delete state,
run destroy, or force-import resources as a shortcut.

Authenticate through Azure CLI or configured ARM OIDC, then review a saved plan in
the authoritative workspace. Check replacements, AKS node-pool rotation requirements,
resource sizing, quota, costs, current supported AKS versions, API allowed IPs, and
existing ACR credential consumers before any later apply. Terraform validation can
be completed without provisioning or starting Azure resources.

## 4. Configure GitHub release identity and gates

Create a GitHub environment named `release`, scoped to the protected release branch.
Configure an Azure federated credential whose subject matches
`repo:jaberyassine/purely:environment:release`. Grant its identity AcrPush at the
non-ABAC ACR scope; it does not require AKS access. Existing Terraform ACR is non-ABAC.

Environment variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, `ACR_NAME`, `ACR_LOGIN_SERVER`, `SONAR_ORGANIZATION`.
Secret: `SONAR_TOKEN`, authorized for the project's Sonar organization/projects.
The final PR job uses repository context; also configure repository variable
`ACR_LOGIN_SERVER` to the same registry value.

Confirm Sonar project keys (`<service>-ms`, `frontend-ms`), gate definitions, GitHub
Actions permissions to create PRs, and branch protections. If PRs created with the
default GITHUB_TOKEN do not trigger required checks, manually trigger checks or use
an appropriately scoped GitHub App; do not weaken branch protection to bypass checks.
All ten image jobs must succeed before a release PR can be proposed.
Published release tags are locked against overwrite/deletion. If a partial release
has already published some images, do not overwrite them on a rerun; review the
failure and create a new source commit/release. Locking images requires the release
identity to have the registry metadata permissions included by the configured role.

The first security scan may reveal vulnerabilities in existing Spring dependencies
or base images. Fix or explicitly review findings; the workflow deliberately does
not silently ignore them. Actions are version-tagged, not SHA-pinned; pin reviewed
action commits before treating the pipeline as production-grade.

## 5. Later bootstrap order (not performed during preparation)

1. Review the real Terraform plan; start/update AKS only when explicitly ready.
2. Confirm AKS-to-ACR image pull, API access, node capacity, and DNS.
3. Install/use the existing Argo CD instance with access to the correct Git branch.
4. Create namespaces and the runtime Secrets listed above.
5. Apply `k8s/argocd/project.yaml`, then the monitoring Application. Wait for its
   health and monitoring CRDs before creating observability and workload Applications.
6. Build the first release and merge its reviewed image-version PR into Git.
7. Apply the observability and workload Applications and wait for Synced/Healthy.
8. Point application DNS to the frontend LoadBalancer, verify certificate trust,
   same-origin API routing, probes, metrics, and application actions.

Application sync-wave annotations do not enforce cross-Application startup order
when Applications are applied independently. Follow the explicit order above.
Inspect resources left by old Grafana/Prometheus/Ingress installations; removing
their local YAML does not uninstall previously deployed Applications or load balancers.
Inventory them before a deliberate cleanup to avoid data loss or duplicate billing.
