[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$private = Join-Path $project '.validation\private-runtime'
$report = Join-Path $project ('.validation\business-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$python = (Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$roots = 'C:\Program Files\Git\mingw64\etc\ssl\cert.pem'
foreach ($path in @($config,$roots,(Join-Path $private 'database-users.json'),(Join-Path $private 'mailbox-users.json'),(Join-Path $private 'ca.crt'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required existing runtime file is missing: $path" }
}
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
# Refresh the private directory ACL before generating any fixture credentials.
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Invoke-Native 'icacls.exe' @($private,'/inheritance:r','/grant:r',"*${sid}:(OI)(CI)F",'*S-1-5-18:(OI)(CI)F') | Out-Null
& (Join-Path $PSScriptRoot 'Test-PurelyDeployment.ps1') -WorkspaceRoot $WorkspaceRoot
if (-not $?) { throw 'Deployment verification failed; business fixtures were not started.' }
if (Get-NetTCPConnection -State Listen -LocalPort 18025 -ErrorAction SilentlyContinue) { throw 'Local mailbox verification port 18025 is in use. No existing process was stopped.' }
New-Item -ItemType Directory -Path $report -Force | Out-Null
$forward = $null
try {
    $outLog = Join-Path $report 'mailbox-forward-out.log'
    $errLog = Join-Path $report 'mailbox-forward-error.log'
    $forward = Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n','purely-data','port-forward','service/mailpit','18025:8025','--address=127.0.0.1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready = $false
    for ($attempt=0;$attempt -lt 20;$attempt++) {
        if ($forward.HasExited) { throw "The owned mailbox port-forward exited. See $errLog" }
        if ((Test-Path -LiteralPath $outLog) -and (Get-Content -LiteralPath $outLog -Raw) -match 'Forwarding from') { $ready=$true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'The mailbox verification port-forward was not ready.' }
    Write-Host '[VERIFY] Repairing the collection-scoped user directory and exercising reserved demo accounts, catalog, cart and order APIs.'
    & $python (Join-Path $PSScriptRoot 'complete-demo.py') $WorkspaceRoot $kubectl $roots $report | Tee-Object -FilePath (Join-Path $report 'business-console.log') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Business verification failed. See $report\business-results.csv" }
} finally {
    if ($forward -and -not $forward.HasExited) { Stop-Process -Id $forward.Id -ErrorAction SilentlyContinue }
}
Write-Host "[PASS] Business flow checks completed. Reports: $report"
Write-Host "Demo credentials stay private: $private\demo-accounts.json"
Write-Host 'Only reserved demo accounts/catalog/cart/orders were used. Email stayed inside Mailpit; no payment was processed.'
