[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ReportDirectory
)
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$report = if ($ReportDirectory) { $ReportDirectory } else { Join-Path $project ('.validation\deployment-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$endpointPath = Join-Path $project '.validation\frontend-tls\endpoint.json'
$endpoint = Get-Content -LiteralPath $endpointPath -Raw | ConvertFrom-Json
if ($endpoint.Domain -notmatch '^purely-demo-71154f86(\.[a-z0-9-]+)?\.eastus\.cloudapp\.azure\.com$') { throw 'Unexpected frontend endpoint.' }
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$python = (Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$roots = 'C:\Program Files\Git\mingw64\etc\ssl\cert.pem'
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
. (Join-Path $PSScriptRoot 'runtime\Prometheus-Service.ps1')
New-Item -ItemType Directory -Path $report -Force | Out-Null
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if (-not $?) { throw 'The dedicated AKS connection check failed.' }
$services = ((Invoke-Kubectl @('get','services','-n','monitoring','-o','json') | Out-String) | ConvertFrom-Json).items
$prometheus = Select-PrometheusApiService -Services @($services)
Write-Host "[VERIFY] Prometheus API Service: $($prometheus.metadata.name)"
if (Get-NetTCPConnection -State Listen -LocalPort 19090 -ErrorAction SilentlyContinue) { throw 'Local verification port 19090 is already in use. No existing process was stopped.' }
$forward = $null
try {
    $outLog = Join-Path $report 'prometheus-forward-out.log'
    $errLog = Join-Path $report 'prometheus-forward-error.log'
    $forward = Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n','monitoring','port-forward',('service/' + $prometheus.metadata.name),'19090:9090','--address=127.0.0.1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready = $false
    for ($attempt=0;$attempt -lt 20;$attempt++) {
        if ($forward.HasExited) { throw "The owned metrics port-forward exited. See $errLog" }
        if ((Test-Path -LiteralPath $outLog) -and (Get-Content -LiteralPath $outLog -Raw) -match 'Forwarding from') { $ready=$true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'The metrics verification port-forward was not ready.' }
    Invoke-Native $python @((Join-Path $PSScriptRoot 'verify-deployment.py'),$endpointPath,$roots) | Tee-Object -FilePath (Join-Path $report 'smoke-results.json') | Out-Host
} finally {
    if ($forward -and -not $forward.HasExited) { Stop-Process -Id $forward.Id -ErrorAction SilentlyContinue }
}
Invoke-Kubectl @('get','applications','-n','argocd') | Out-Host
Invoke-Kubectl @('get','deployments','-A') | Out-Host
Write-Host "[PASS] Public application TLS/HTML/HSTS, actuator blocking and all nine backend metrics namespaces verified: https://$($endpoint.Domain)"
Write-Host "Reports: $report"
Write-Host 'No application deployment, restart or cluster configuration change was performed by this verification script.'
