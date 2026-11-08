# Temporary AKS interview demo: plan first

Run `scripts/Prepare-AzureDemo.ps1` from a normal PowerShell session after signing
in to the new subscription. It does not run Terraform apply.

The script pins subscription `71154f86-51d1-45c8-8ace-4f861544bddd` and tenant
`3b2aa7a4-8d37-45ac-a4fe-c161cb5e452b`, checks quotas and SKU restrictions,
checks the proposed globally unique registry name, and registers only the Azure
resource providers needed by this configuration. Provider registration is a
subscription configuration change; it does not deploy the cluster.

It copies Terraform source and the dependency lockfile into a fresh sibling
directory, `purely-azure-demo`. No previous Terraform backend, state, tfvars or
provider installation is copied. An existing destination or existing `purely-demo-rg`
in the new subscription stops the script for review.

Demo inputs:

- East US, two `Standard_D4s_v4` nodes (8 vCPUs total).
- ACR Basic, proposed name `purelyys71154f86`, admin authentication disabled.
- Existing RSA public key from `$env:USERPROFILE/.ssh/id_rsa.pub`; pass
  `-SshPublicKeyPath` to choose another RSA public key. No private key is copied.
- AKS API allowlist limited to the operator's current IPv4 address, retrieved
  over HTTPS from api.ipify.org. Update it if the public IP changes.
- Dedicated resource group `purely-demo-rg`, cluster `purely-demo-aks`,
  network prefix `purely-demo` and log workspace `purely-demo-logs`.
  Original Terraform resource addresses are retained; the original subscription
  and its state are not used. Do not apply these demo changes against old state.
- AKS Free management tier, Ubuntu nodes, managed 128-GB OS disks, Azure CNI
  with 30 pods per node, Standard load balancer and outbound connectivity.
  Kubernetes creates frontend load balancer rules/public IPs from its Service;
  Terraform does not duplicate the frontend Service's public IP.
- User-assigned control-plane identity with Network Contributor restricted to
  the custom subnet, created before the cluster; kubelet AcrPull on ACR only.
- Log Analytics: 30-day retention and a 1-GB/day ingestion cap. This cap is not
  a hard spending limit; enforcement can lag and some data can be exempt.
  Resource tags identify the project, demo environment and Terraform ownership.

The script runs format, init with the existing lockfile, validate and plan.
Review `demo.tfplan` and the terminal summary before any apply. SKU restrictions
being empty does not guarantee physical capacity at deployment time. Budget
estimates must include disks, load balancing, public IPs, registry, monitoring,
network traffic and the application's database arrangements. This step does not
verify or deploy application secrets, MongoDB, TLS, Argo CD or application images.

## Node upgrade constraint

Observed regional quota is 12 vCPUs and DSv4 quota is 10, with zero usage.
The two 4-vCPU nodes fit, but a third same-family surge node does not fit the
current family quota. Resolve surge capacity before initiating a node upgrade;
do not claim upgrade readiness from a successful initial plan or deployment.

## State, evidence and cleanup

Keep `purely-azure-demo` securely until the demo resources have been destroyed
and cleanup verified. Its eventual Terraform state is sensitive and must never
be published. Do not delete this directory as a substitute for destroying cloud
resources. Keep screenshots and the video separately so they survive cleanup.

Local checks for this change: Terraform formatting, module/provider discovery,
configuration policy and PowerShell parse/ASCII checks passed. Provider
execution remains restricted in the assistant environment.

The operator subsequently ran the script successfully on 2026-11-08: Terraform
init and validate passed, and the saved plan reported **9 to add, 0 to change,
0 to destroy**. The provided complete plan output was reviewed: resource group,
VNet, subnet, ACR Basic (admin disabled), Log Analytics (1 GB/day, 30 days),
control-plane identity, subnet role assignment, AKS Free (two D4s_v4 Ubuntu
nodes) and kubelet AcrPull. API access is scoped to the operator's IPv4 /32.
The plan is in the isolated `purely-azure-demo/demo.tfplan`. This is a plan
review, not evidence that apply or application deployment has succeeded.
