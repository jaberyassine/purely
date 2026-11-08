# Local preparation
Run the validation script before a deployment. No script in this directory provisions Azure resources.

`Get-AksPreflight.ps1` inventories the Azure account, expected AKS/ACR resources
and node pools without resource changes. Run in normal PowerShell with Azure CLI
signed in. Review its JSON/CSV report before preparing a real Terraform plan.

`Test-Integration.ps1` runs full validation, rebuilds/scans images, then runs HTTPS
smoke and real MongoDB-backed signup, login, cart, order and ownership checks with
disposable fixtures. See `docs/INTEGRATION-TEST.md` for isolation and resource needs.
