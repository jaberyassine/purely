[CmdletBinding()]
param(
    [string]$ResourceGroup = 'dev-rg',
    [string]$ClusterName = 'dev-aks',
    [string]$RegistryName = 'purelyacr'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$reportDirectory = Join-Path $projectRoot ('.validation\aks-preflight\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$commandLog = Join-Path $reportDirectory 'commands.log'
$results = [System.Collections.Generic.List[object]]::new()
$azure = Get-Command az.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1
function Read-AzureJson {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $raw = & $azure.Path @Arguments --only-show-errors --output json 2>> $commandLog
    if ($LASTEXITCODE -ne 0) { throw "Azure read failed. See $commandLog" }
    return (($raw | Out-String) | ConvertFrom-Json)
}
function Read-Check {
    param([string]$Name,[string[]]$Arguments)
    try {
        $value = Read-AzureJson $Arguments
        if ($null -eq $value) { throw 'Azure returned no data.' }
        $value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportDirectory ($Name + '.json')) -Encoding UTF8
        $results.Add([pscustomobject]@{Check=$Name;Status='PASS';Details='Read completed; this is not deployment approval'})
        Write-Host "[PASS] $Name"
        return $value
    } catch {
        $results.Add([pscustomobject]@{Check=$Name;Status='FAIL';Details=$_.Exception.Message})
        Write-Host "[FAIL] $Name - $($_.Exception.Message)"
        return $null
    }
}
try {
    $account = Read-Check 'account' @('account','show','--query','{name:name,id:id,tenantId:tenantId,state:state}')
    if (-not $account) { throw 'Sign in with az login in this PowerShell, then rerun. No Azure resources were changed.' }
    Write-Host ('Subscription: ' + $account.name + ' (' + $account.id + ')')
    $subscription = [string]$account.id
    # Explicitly scope every resource lookup to the same account; do not switch accounts.
    $group = Read-Check 'resource-group' @('group','show','--name',$ResourceGroup,'--subscription',$subscription,
        '--query','{name:name,location:location,state:properties.provisioningState}')
    if (-not $group) { throw 'Expected resource group was not readable. Check the selected subscription and names.' }
    $cluster = Read-Check 'aks' @('aks','show','--resource-group',$ResourceGroup,'--name',$ClusterName,
        '--subscription',$subscription,'--query',
        '{name:name,resourceGroup:resourceGroup,location:location,power:powerState.code,provisioningState:provisioningState,kubernetesVersion:kubernetesVersion,dnsServiceIP:networkProfile.dnsServiceIp,serviceCidr:networkProfile.serviceCidr,nodeResourceGroup:nodeResourceGroup,privateCluster:apiServerAccessProfile.enablePrivateCluster,authorizedIPRanges:apiServerAccessProfile.authorizedIpRanges}')
    $registry = Read-Check 'acr' @('acr','show','--resource-group',$ResourceGroup,'--name',$RegistryName,
        '--subscription',$subscription,'--query','{name:name,loginServer:loginServer,sku:sku.name,adminEnabled:adminUserEnabled,provisioningState:provisioningState,roleAssignmentMode:roleAssignmentMode}')
    if ($cluster) {
        $pools = Read-Check 'node-pools' @('aks','nodepool','list','--resource-group',$ResourceGroup,
            '--cluster-name',$ClusterName,'--subscription',$subscription,'--query',
            '[].{name:name,vmSize:vmSize,count:count,version:orchestratorVersion,power:powerState.code,state:provisioningState}')
        $cluster | Format-List
        if ($cluster.dnsServiceIP -ne '10.1.0.10') {
            $results.Add([pscustomobject]@{Check='frontend-dns';Status='REVIEW';Details=('Frontend resolver is 10.1.0.10; actual AKS DNS is ' + $cluster.dnsServiceIP)})
            Write-Host '[REVIEW] Frontend DNS resolver must match the actual AKS DNS before release.'
        }
        if ($pools) { $pools | Format-Table -AutoSize }
    }
    if ($registry) { $registry | Format-List }
} finally {
    $results | Export-Csv -LiteralPath (Join-Path $reportDirectory 'preflight-results.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Report: $reportDirectory"
    Write-Host 'Read-only inventory complete. No cluster start, Terraform apply, credentials export, image push or deployment was performed.'
}
if (@($results | Where-Object Status -eq 'FAIL').Count) { throw 'Resolve failed inventory reads before continuing.' }
