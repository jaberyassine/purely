[CmdletBinding()]
param(
    [string]$SshPublicKeyPath = (Join-Path $env:USERPROFILE '.ssh\id_rsa.pub')
)
$ErrorActionPreference = 'Stop'
$subscription = '71154f86-51d1-45c8-8ace-4f861544bddd'
$tenant = '3b2aa7a4-8d37-45ac-a4fe-c161cb5e452b'
$project = Split-Path -Parent $PSScriptRoot
$demo = Join-Path (Split-Path -Parent $project) 'purely-azure-demo'
$registry = 'purelyys71154f86'
$resourceGroup = 'purely-demo-rg'
$azure = (Get-Command az.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
$terraform = (Get-Command terraform.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path

function Read-Azure {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $raw = & $azure @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw ('Azure command failed: ' + ($Arguments -join ' ')) }
    return (($raw | Out-String) | ConvertFrom-Json)
}
function Invoke-Terraform {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    & $terraform "-chdir=$demo" @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not ($Arguments[0] -eq 'plan' -and $code -eq 2)) {
        throw "Terraform failed (exit $code). No apply was requested."
    }
}

# Pin account and identity before any subscription mutation.
Write-Host '[CHECK] New subscription and local SSH public key.'
$account = Read-Azure @('account','show')
if ($account.id -ne $subscription -or $account.tenantId -ne $tenant -or $account.state -ne 'Enabled') {
    throw 'Select the new Azure subscription first. This script cannot use the old account.'
}
foreach ($entry in @('ARM_CLIENT_ID','ARM_CLIENT_SECRET','ARM_CLIENT_CERTIFICATE_PATH','ARM_USE_MSI','ARM_USE_OIDC','ARM_ACCESS_KEY','TF_WORKSPACE','TF_CLI_ARGS','TF_CLI_ARGS_init','TF_CLI_ARGS_plan','TF_DATA_DIR')) {
    if ([Environment]::GetEnvironmentVariable($entry)) { throw "Unset $entry in this shell before running the isolated demo plan." }
}
if (-not (Test-Path -LiteralPath $SshPublicKeyPath -PathType Leaf) -or $SshPublicKeyPath -notlike '*.pub') {
    throw 'An existing SSH public key (.pub) is required. Pass -SshPublicKeyPath with its path.'
}
$publicKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
if ($publicKey -notmatch '^ssh-rsa\s+[A-Za-z0-9+/=]+(?:\s|$)') {
    throw 'Use an RSA OpenSSH public key for this AKS configuration.'
}
# Fail closed if this directory was used previously; do not overwrite any state or plan.
if (Test-Path -LiteralPath $demo) {
    throw "Demo directory already exists: $demo. Keep it for its state; review it before retrying."
}
if (Read-Azure @('group','exists','--name',$resourceGroup,'--subscription',$subscription)) {
    throw "$resourceGroup already exists in the new subscription. Review existing resources before planning."
}
Write-Host '[CHECK] Registry name, East US quotas and D4s_v4 restrictions.'
$availability = Read-Azure @('acr','check-name','--name',$registry,'--subscription',$subscription)
if (-not $availability.nameAvailable) { throw "ACR name $registry is unavailable. No files were created." }
$quota = @(Read-Azure @('vm','list-usage','--location','eastus','--subscription',$subscription))
$regional = @($quota | Where-Object { $_.name.value -ieq 'cores' })
$family = @($quota | Where-Object { $_.name.value -ieq 'standardDSv4Family' })
if ($regional.Count -ne 1 -or $family.Count -ne 1) { throw 'Could not identify regional/DSv4 quotas.' }
if (($regional[0].limit - $regional[0].currentValue) -lt 8 -or ($family[0].limit - $family[0].currentValue) -lt 8) {
    throw 'At least 8 unused regional and DSv4 vCPUs are required.'
}
$skus = @(Read-Azure @('vm','list-skus','--location','eastus','--size','Standard_D4s_v4','--resource-type','virtualMachines','--all','--subscription',$subscription))
$sku = @($skus | Where-Object { $_.name -eq 'Standard_D4s_v4' })
if ($sku.Count -ne 1 -or @($sku[0].restrictions).Count -gt 0) {
    throw 'D4s_v4 has restrictions or was not found. Review SKU availability before continuing.'
}
$operatorIp = ([string](Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 20)).Trim()
$parsedIp = $null
if (-not [Net.IPAddress]::TryParse($operatorIp, [ref]$parsedIp) -or $parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'Could not determine an IPv4 address for the API allowlist.'
}

# Register only providers used by this demo. This creates no cluster or VM.
foreach ($namespace in @('Microsoft.Compute','Microsoft.Network','Microsoft.ContainerService','Microsoft.ContainerRegistry','Microsoft.ManagedIdentity','Microsoft.OperationalInsights','Microsoft.OperationsManagement')) {
    $provider = Read-Azure @('provider','show','--namespace',$namespace,'--subscription',$subscription)
    if ($provider.registrationState -ne 'Registered') {
        Write-Host "[REGISTER] $namespace - this can take several minutes."
        Read-Azure @('provider','register','--namespace',$namespace,'--subscription',$subscription,'--wait') | Out-Null
    }
}

# Copy only reviewed Terraform code and lockfile; never old state, backend or tfvars.
New-Item -ItemType Directory -Path $demo | Out-Null
$source = Join-Path $project 'infra'
foreach ($name in @('main.tf','variables.tf','outputs.tf','.terraform.lock.hcl')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $demo
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $source 'modules') -Recurse -File -Filter '*.tf') {
    $relative = $file.FullName.Substring($source.Length).TrimStart('\')
    $destination = Join-Path $demo $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
}
Copy-Item -LiteralPath $SshPublicKeyPath -Destination (Join-Path $demo 'operator.pub')
$inputs = @{
    subscription_id = $subscription
    tenant_id = $tenant
    acr_name = $registry
    ssh_public_key_path = 'operator.pub'
    api_authorized_ip_ranges = @("$operatorIp/32")
    node_count = 2
    node_vm_size = 'Standard_D4s_v4'
    skip_provider_registration = $true
    resource_group_name = $resourceGroup
    cluster_name = 'purely-demo-aks'
    network_name_prefix = 'purely-demo'
    log_analytics_name = 'purely-demo-logs'
    location = 'eastus'
    log_daily_quota_gb = 1
}
$inputs | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $demo 'terraform.tfvars.json') -Encoding ASCII
@'
# Local deployment data: keep this directory until cleanup has completed.
.terraform/
terraform.tfvars.json
*.tfstate*
*.tfplan
operator.pub
*.log
'@ | Set-Content -LiteralPath (Join-Path $demo '.gitignore') -Encoding ASCII
Write-Host "[PLAN] Isolated demo directory: $demo"
Write-Host '[LIMIT] DSv4 quota currently does not allow a third 4-vCPU node if the limit is 10. Do not run node upgrades before resolving surge capacity.'
Invoke-Terraform @('fmt','-recursive')
Invoke-Terraform @('init','-input=false','-lockfile=readonly')
Invoke-Terraform @('validate')
Invoke-Terraform @('plan','-input=false','-detailed-exitcode','-out=demo.tfplan','-no-color')
Write-Host "[READY] Review the plan above. Keep $demo for apply and later destroy."
Write-Host 'No Terraform apply, AKS creation, image push or GitHub merge was performed.'
