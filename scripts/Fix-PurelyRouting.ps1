[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$project=Join-Path $WorkspaceRoot 'purely-ready'
$config=Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$kubectl='C:\kubectl\kubectl.exe'
$python=(Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$report=Join-Path $project ('.validation\routing-fix-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $report -Force | Out-Null
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if(-not $?){throw 'Cluster connection failed.'}
$app=(Invoke-Kubectl @('get','application','service-registry','-n','argocd','-o','json') | Out-String) | ConvertFrom-Json
if($app.spec.source.repoURL -ne 'https://github.com/jaberyassine/purely.git' -or $app.spec.source.path -ne 'k8s/charts/service-registry' -or -not $app.spec.source.helm){throw 'Unexpected registry Application; stop before modification.'}
$service=(Invoke-Kubectl @('get','service','service-registry','-n','service-registry','-o','json') | Out-String) | ConvertFrom-Json
if($service.spec.type -ne 'ClusterIP' -or @($service.spec.ports).Count -ne 1 -or $service.spec.ports[0].targetPort -ne 8761 -or $service.spec.ports[0].port -notin @(80,8761)){throw 'Unexpected registry Service port mapping.'}
@{Source=$app.spec.source;PreviousServicePort=$service.spec.ports[0].port;NewServicePort=8761} | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $report 'before.json') -Encoding UTF8
$parameters=@($app.spec.source.helm.parameters | Where-Object {$_ -and $_.name -ne 'service.port'}) + @(@{name='service.port';value='8761'})
$patch=@(@{op='test';path='/metadata/resourceVersion';value=$app.metadata.resourceVersion},@{op='add';path='/spec/source/helm/parameters';value=$parameters})
$patchFile=Join-Path $report 'registry-port-patch.json'
ConvertTo-Json -InputObject $patch -Depth 20 | Set-Content $patchFile -Encoding UTF8
Write-Host '[FIX] Setting the registry Helm Service port to 8761 through Argo CD, matching all Eureka clients.'
Invoke-Kubectl @('patch','application','service-registry','-n','argocd','--type=json','--patch-file',$patchFile) | Out-Host
Invoke-Kubectl @('annotate','application','service-registry','-n','argocd','argocd.argoproj.io/refresh=hard','--overwrite') | Out-Host
$ready=$false
for($attempt=0;$attempt -lt 60;$attempt++){
    $service=(Invoke-Kubectl @('get','service','service-registry','-n','service-registry','-o','json') | Out-String) | ConvertFrom-Json
    if($service.spec.ports[0].port -eq 8761){$ready=$true;break}
    Start-Sleep -Seconds 3
}
if(-not $ready){throw "Argo CD has not applied the registry port. Review $report"}
if(Get-NetTCPConnection -State Listen -LocalPort 18761 -ErrorAction SilentlyContinue){throw 'Local registry verification port is in use. No process was stopped.'}
$forward=$null
try{
    $outLog=Join-Path $report 'registry-forward-out.log'
    $errLog=Join-Path $report 'registry-forward-error.log'
    $forward=Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n','service-registry','port-forward','service/service-registry','18761:8761','--address=127.0.0.1') -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready=$false
    for($attempt=0;$attempt -lt 20;$attempt++){
        if($forward.HasExited){throw "Registry verification tunnel exited. See $errLog"}
        if((Test-Path $outLog) -and (Get-Content $outLog -Raw) -match 'Forwarding from'){$ready=$true;break}
        Start-Sleep -Seconds 1
    }
    if(-not $ready){throw 'Registry verification tunnel was not ready.'}
    & $python (Join-Path $PSScriptRoot 'verify-routing.py') $project $report
    if($LASTEXITCODE -ne 0){throw "Routing verification failed. Reports: $report"}
}finally{if($forward -and -not $forward.HasExited){Stop-Process -Id $forward.Id -ErrorAction SilentlyContinue}}
Write-Host '[PASS] Registry and public API routing verified. Continuing with reserved demo catalog and checkout checks.'
& (Join-Path $PSScriptRoot 'Finish-PurelyDemo.ps1') -WorkspaceRoot $WorkspaceRoot
