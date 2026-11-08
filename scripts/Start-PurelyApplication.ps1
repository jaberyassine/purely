[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$checkout = Join-Path $WorkspaceRoot 'purely-github-20261108-073314-374bc2'
$report = Join-Path $project ('.validation\application-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$private = Join-Path $project '.validation\private-runtime'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$endpointPath = Join-Path $project '.validation\frontend-tls\endpoint.json'
$endpoint = Get-Content -LiteralPath $endpointPath -Raw | ConvertFrom-Json
if ($endpoint.Domain -notmatch '^purely-demo-71154f86(\.[a-z0-9-]+)?\.eastus\.cloudapp\.azure\.com$') { throw 'Unexpected frontend domain.' }
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$python = (Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Path
$roots = 'C:\Program Files\Git\mingw64\etc\ssl\cert.pem'
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
function Read-Git {
    param([string[]]$Arguments)
    Invoke-Native $git (@('-c',('safe.directory=' + $checkout.Replace('\','/')),'-C',$checkout) + $Arguments)
}
New-Item -ItemType Directory -Path $report -Force | Out-Null
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if (-not $?) { throw 'The dedicated AKS connection check failed.' }
Read-Git @('fetch','origin','master') | Out-Host
$revision = (Read-Git @('rev-parse','FETCH_HEAD') | Out-String).Trim()
if ($revision -notmatch '^[a-f0-9]{40}$') { throw 'Could not identify the reviewed master revision.' }
$frontendValues = Read-Git @('show',("${revision}:k8s/charts/frontend/values.yaml")) | Out-String
$monitoring = Read-Git @('show',("${revision}:k8s/argocd/monitoring-app.yaml")) | Out-String
if ($frontendValues -notmatch 'azure-dns-label-name: purely-demo-71154f86' -or $monitoring -notmatch "targetRevision: '92.22.0'") { throw 'The frontend/monitoring configuration PR must be merged before application bootstrap.' }
$services = @('auth-service','user-service','product-service','category-service','cart-service','order-service')
foreach ($service in $services) {
    $values = Read-Git @('show',("${revision}:k8s/charts/$service/values.yaml")) | Out-String
    if ($values -notmatch 'runtimeTrust:' -or $values -notmatch 'truststore.p12') { throw "Internal TLS trust is missing for $service." }
}
# Enumerate explicit namespace/name pairs without flattening arrays in PowerShell 5.1.
$required = [System.Collections.Generic.List[object]]::new()
foreach ($service in $services) {
    $required.Add(@{Namespace=$service;Name='mongodb-secret'})
    $required.Add(@{Namespace=$service;Name='runtime-trust'})
}
foreach ($pair in @(@{Namespace='auth-service';Name='auth-secret'},@{Namespace='notification-service';Name='smtp-secret'},@{Namespace='notification-service';Name='runtime-trust'},@{Namespace='frontend';Name='purely-tls'})) { $required.Add($pair) }
foreach ($pair in $required) { Invoke-Kubectl @('get','secret',$pair.Name,'-n',$pair.Namespace,'-o','name') | Out-Host }
$svc = ((Invoke-Kubectl @('get','service','frontend','-n','frontend','-o','json') | Out-String) | ConvertFrom-Json)
if (@($svc.status.loadBalancer.ingress | Where-Object { $_.ip -eq $endpoint.IP }).Count -ne 1) { throw 'The frontend Service no longer has the certificate endpoint IP.' }
foreach ($name in @('mongodb','mailpit')) {
    $state = (Invoke-Kubectl @('get','statefulset',$name,'-n','purely-data','-o','json') | Out-String) | ConvertFrom-Json
    if ($state.status.readyReplicas -ne 1) { throw "$name is not Ready. Review it before application deployment." }
}

# Download only public manifests from the exact fetched Git revision.
$argo = Join-Path $report 'argocd'
New-Item -ItemType Directory -Path $argo -Force | Out-Null
$applications = @('service-registry','auth-service','user-service','product-service','category-service','cart-service','order-service','notification-service','api-gateway','frontend')
foreach ($name in (@('project','monitoring-app','observability-app') + @($applications | ForEach-Object { $_ + '-app' }))) {
    $path = "k8s/argocd/$name.yaml"
    Read-Git @('show',("${revision}:$path")) | Set-Content -LiteralPath (Join-Path $argo ($name + '.yaml')) -Encoding ASCII
}
# Older reviewed revisions may predate the Argo CD 3.6 CRD-bootstrap diff fix.
# Keep ServerSideApply=true for large CRDs; use legacy diff only for this Application.
$monitorFile = Join-Path $argo 'monitoring-app.yaml'
$monitorText = Get-Content -LiteralPath $monitorFile -Raw
if ($monitorText -notmatch 'argocd.argoproj.io/compare-options:') {
    $replacement = '$0' + "`n    argocd.argoproj.io/compare-options: ServerSideDiff=false"
    $monitorText = $monitorText -replace '(?m)^(\s*)argocd\.argoproj\.io/sync-wave: "0"\r?$', $replacement
    $monitorText | Set-Content -LiteralPath $monitorFile -Encoding ASCII
}
if ($monitorText -notmatch 'argocd.argoproj.io/compare-options: ServerSideDiff=false') { throw 'Unexpected monitoring diff configuration. Stop for review.' }
@{ReviewedMaster=$revision;Frontend=$endpoint.Domain;Applications=$applications;MonitoringChart='92.22.0'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $report 'plan.json') -Encoding ASCII
function Wait-ArgoApplication {
    param([string]$Name,[int]$TimeoutSeconds=900)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $errorGrace = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        $app = ((Invoke-Kubectl @('get','application',$Name,'-n','argocd','-o','json') | Out-String) | ConvertFrom-Json)
        $problems = @($app.status.conditions | Where-Object { $_.type -in @('ComparisonError','InvalidSpecError','SyncError') })
        # A re-apply may still expose conditions from the previous reconcile.
        if ($problems.Count -gt 0 -and [DateTime]::UtcNow -ge $errorGrace) { $problems | Select-Object type,message | Format-List | Out-Host; throw "Argo CD cannot reconcile $Name." }
        if ($problems.Count -eq 0 -and $app.status.sync.status -eq 'Synced' -and $app.status.health.status -eq 'Healthy') { Write-Host "[PASS] Argo CD ${Name}: Synced / Healthy"; return }
        if ($app.status.operationState.phase -in @('Failed','Error') -and [DateTime]::UtcNow -ge $errorGrace) { $app.status.operationState.message | Out-Host; throw "Argo CD sync failed for $Name." }
        Start-Sleep -Seconds 5
    }
    Invoke-Kubectl @('get','pods','-A') | Out-Host
    throw "Timed out waiting for Argo CD $Name. Existing resources were left for inspection."
}

Apply-Object @{apiVersion='v1';kind='Namespace';metadata=@{name='monitoring';labels=@{'purely.io/runtime'='demo-v1'}}}
$grafanaPath = Join-Path $private 'monitoring-users.json'
if (-not (Test-Path -LiteralPath $grafanaPath)) {
    $old = (Invoke-Kubectl @('get','secret','grafana-admin','-n','monitoring','--ignore-not-found','-o','name') | Out-String).Trim()
    if ($old) { throw 'Existing Grafana credentials have no matching local backup.' }
    @{user='demo-admin';password=(New-HexPassword)} | ConvertTo-Json | Set-Content -LiteralPath $grafanaPath -Encoding ASCII
}
$grafana = Get-Content -LiteralPath $grafanaPath -Raw | ConvertFrom-Json
Apply-Secret 'monitoring' 'grafana-admin' @{'admin-user'=$grafana.user;'admin-password'=$grafana.password}
Write-Host '[DEPLOY] Monitoring first; application ServiceMonitor resources require its CRDs.'
Invoke-Kubectl @('apply','-f',(Join-Path $argo 'monitoring-app.yaml')) | Out-Host
Wait-ArgoApplication 'monitoring'
foreach ($crd in @('servicemonitors.monitoring.coreos.com','prometheusrules.monitoring.coreos.com')) { Invoke-Kubectl @('wait','--for=condition=Established',('crd/' + $crd),'--timeout=120s') | Out-Host }
Invoke-Kubectl @('apply','-f',(Join-Path $argo 'observability-app.yaml')) | Out-Host
Wait-ArgoApplication 'purely-observability'
Invoke-Kubectl @('apply','-f',(Join-Path $argo 'project.yaml')) | Out-Host
Invoke-Kubectl @('apply','-f',(Join-Path $argo 'service-registry-app.yaml')) | Out-Host
Wait-ArgoApplication 'service-registry' 600
foreach ($name in ($applications | Where-Object { $_ -notin @('service-registry','frontend') })) { Invoke-Kubectl @('apply','-f',(Join-Path $argo ($name + '-app.yaml'))) | Out-Host }
foreach ($name in ($applications | Where-Object { $_ -notin @('service-registry','frontend') })) { Wait-ArgoApplication $name 600 }

# The same field manager originally owned port 80; omitting it now removes that entry.
# Keep the existing Service and Azure IP, then let Argo CD reconcile the same desired HTTPS mapping.
Apply-Object @{apiVersion='v1';kind='Service';metadata=@{name='frontend';namespace='frontend';labels=@{'purely.io/bootstrap'='tls-acme-v1'};annotations=@{'service.beta.kubernetes.io/azure-dns-label-name'=$endpoint.Label}};spec=@{type='LoadBalancer';selector=@{app='frontend'};ports=@(@{name='https';port=443;targetPort='https';protocol='TCP'})}}
$svc = (Invoke-Kubectl @('get','service','frontend','-n','frontend','-o','json') | Out-String) | ConvertFrom-Json
if (@($svc.spec.ports).Count -ne 1 -or $svc.spec.ports[0].port -ne 443) { throw 'The certificate-only HTTP port was not removed. Review the Service before exposing the frontend.' }
Invoke-Kubectl @('apply','-f',(Join-Path $argo 'frontend-app.yaml')) | Out-Host
Wait-ArgoApplication 'frontend' 600

$services = ((Invoke-Kubectl @('get','services','-n','monitoring','-o','json') | Out-String) | ConvertFrom-Json).items
$prometheus = @($services | Where-Object { $_.spec.selector.prometheus -and @($_.spec.ports | Where-Object port -eq 9090).Count -gt 0 })
if ($prometheus.Count -ne 1) { throw 'Could not uniquely identify the Prometheus API service.' }
if (Get-NetTCPConnection -State Listen -LocalPort 19090 -ErrorAction SilentlyContinue) { throw 'Local verification port 19090 is already in use. No existing process was stopped.' }
$forward = $null
try {
    $outLog=Join-Path $report 'prometheus-forward-out.log'; $errLog=Join-Path $report 'prometheus-forward-error.log'
    $forward=Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n','monitoring','port-forward',('service/' + $prometheus[0].metadata.name),'19090:9090','--address=127.0.0.1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready=$false
    for($attempt=0;$attempt -lt 20;$attempt++) {
        if($forward.HasExited){throw "The owned metrics port-forward exited. See $errLog"}
        if((Test-Path -LiteralPath $outLog) -and (Get-Content -LiteralPath $outLog -Raw) -match 'Forwarding from'){ $ready=$true; break }
        Start-Sleep -Seconds 1
    }
    if(-not $ready){throw 'The metrics verification port-forward was not ready.'}
    Invoke-Native $python @((Join-Path $PSScriptRoot 'verify-deployment.py'),$endpointPath,$roots) | Tee-Object -FilePath (Join-Path $report 'smoke-results.json') | Out-Host
} finally { if($forward -and -not $forward.HasExited){Stop-Process -Id $forward.Id -ErrorAction SilentlyContinue} }
Invoke-Kubectl @('get','applications','-n','argocd') | Out-Host
Invoke-Kubectl @('get','deployments','-A') | Out-Host
Write-Host "[PASS] Purely is deployed at https://$($endpoint.Domain), with verified TLS and all nine backend metrics namespaces UP."
Write-Host "Reports: $report"
Write-Host 'Next: verify registration, login, catalog, cart and order flow in the deployed application.'
