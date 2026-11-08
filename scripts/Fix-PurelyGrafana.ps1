[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$project=Join-Path $WorkspaceRoot 'purely-ready'
$config=Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$kubectl='C:\kubectl\kubectl.exe'
$python=(Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$report=Join-Path $project ('.validation\grafana-fix-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
. (Join-Path $PSScriptRoot 'runtime\Prometheus-Service.ps1')
if(-not (Get-NetTCPConnection -State Listen -LocalPort 3000 -ErrorAction SilentlyContinue)){throw 'Keep Open-PurelyDashboards.ps1 running first; the local Grafana tunnel is missing.'}
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if(-not $?){throw 'AKS connection failed.'}
$services=((Invoke-Kubectl @('get','services','-n','monitoring','-o','json') | Out-String) | ConvertFrom-Json).items
$prometheus=Select-PrometheusApiService -Services @($services)
$prometheusUrl='http://' + $prometheus.metadata.name + '.monitoring.svc.cluster.local:9090'
New-Item -ItemType Directory -Path $report -Force | Out-Null
& $python (Join-Path $PSScriptRoot 'configure-grafana.py') $project $report $prometheusUrl
if($LASTEXITCODE -ne 0){throw "Grafana setup stopped. See $report\checks.csv"}
Write-Host "Reports: $report"
Write-Host 'Open http://127.0.0.1:3000/d/purely-live-overview and refresh the Grafana home page.'
