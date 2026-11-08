# AKS interview demo status - 2026-11-08

Verified from the operator's Terraform and Kubernetes output:

- Initial apply: 9 resources added, none changed or destroyed.
- Release identity apply: 3 resources added, none changed or destroyed.
- Resource group: `purely-demo-rg`, region: East US.
- Cluster: `purely-demo-aks`, Kubernetes nodes: v1.36.5.
- Two `Standard_D4s_v4` nodes reported Ready; neither has a public node IP.
- AKS service DNS: `10.1.0.10`, matching the frontend resolver configuration.
- Registry: `purelyys71154f86.azurecr.io`, Basic, admin authentication disabled.
- A separate kubeconfig is used; the operator's default kubeconfig is unchanged.
- The GitHub release identity has OIDC trust restricted to
  `repo:jaberyassine/purely:environment:release`, with AcrPush on this ACR.
- The Desktop Terraform project uses a dedicated new-account local backend at
  `state/azure-demo-71154f86/terraform.tfstate`. Original-account state files
  were preserved and verified by hash. Never publish either state or kubeconfig.

## Release gate status

Run `42479783082` passed all 11 validation jobs. All ten image jobs stopped at
Sonar initialization with HTTP 403 from the JRE metadata endpoint; Docker image
build, Trivy, Azure login and image push steps did not run. This was not a
completed code-quality assessment. The operator subsequently replaced the Sonar
token in the release environment; the new token still needs a successful run.

The frontend scan action is updated from v5 to reviewed v8.3.0, pinned to commit
`d209202bc7d53ff1cc128f7f907dac145c9d6ae9`, addressing the action's v5 security
warning. The quality and vulnerability gates remain blocking.

Azure's existing OIDC issuer and node-pool upgrade defaults are explicit in
Terraform to avoid proposing their removal during identity-only plans. The
10-vCPU DSv4 family quota still cannot accommodate a third 4-vCPU surge node;
do not initiate a node upgrade before resolving surge capacity.

## Still required

Successful Sonar/Trivy/OIDC/image push, reviewed GitOps image-version PR,
MongoDB and service-scoped secrets, TLS, Argo CD bootstrap, monitoring and
application deployment/verification. No claim of an end-to-end AKS deployment,
load test, failover test or backup restore is made by this status document.

After screenshots and video are secured, destroy the demo using its authoritative
Terraform state and verify cleanup, including AKS-managed resources. Keep the
state until cleanup has been verified.
