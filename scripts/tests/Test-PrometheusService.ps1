$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\runtime\Prometheus-Service.ps1')
function New-Fixture {
    param([string]$Name,[string]$ClusterIP='10.1.2.3',[int]$Port=9090,[string]$Type='ClusterIP')
    return [pscustomobject]@{metadata=[pscustomobject]@{name=$Name};spec=[pscustomobject]@{type=$Type;clusterIP=$ClusterIP;ports=@([pscustomobject]@{port=$Port})}}
}
$api = New-Fixture 'new-chart-prometheus-api'
$headless = New-Fixture 'prometheus-operated' 'None'
$grafana = New-Fixture 'grafana' '10.1.2.4' 80
if ((Select-PrometheusApiService @($api)).metadata.name -ne $api.metadata.name) { throw 'Single client Service was not selected.' }
if ((Select-PrometheusApiService @($headless,$grafana,$api)).metadata.name -ne $api.metadata.name) { throw 'Headless or unrelated Services were selected.' }
$oldLabels = New-Fixture 'legacy-api'
$oldLabels.spec | Add-Member -NotePropertyName selector -NotePropertyValue @{prometheus='legacy'}
if ((Select-PrometheusApiService @($headless,$oldLabels)).metadata.name -ne $oldLabels.metadata.name) { throw 'Legacy selector compatibility failed.' }
$failed = $false
try { Select-PrometheusApiService @($headless,$grafana) | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'A missing client Service was not rejected.' }
$failed = $false
try { Select-PrometheusApiService @($api,$oldLabels) | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'Ambiguous client Services were not rejected.' }
Write-Host 'PASS: five service-discovery cases (new/old selectors, headless filtering, absent and ambiguous APIs).'
