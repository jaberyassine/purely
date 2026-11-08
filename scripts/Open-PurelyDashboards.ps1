[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$project=Join-Path $WorkspaceRoot 'purely-ready'
$config=Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$kubectl='C:\kubectl\kubectl.exe'
$report=Join-Path $project ('.validation\dashboards-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
. (Join-Path $PSScriptRoot 'runtime\Prometheus-Service.ps1')
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if(-not $?){throw 'AKS connection failed.'}
$services=((Invoke-Kubectl @('get','services','-n','monitoring','-o','json') | Out-String) | ConvertFrom-Json).items
$prometheus=Select-PrometheusApiService -Services @($services)
$grafana=@($services | Where-Object {$_.metadata.name -match '-grafana$' -and $_.spec.type -eq 'ClusterIP' -and @($_.spec.ports | Where-Object {$_.port -eq 80}).Count -eq 1})
if($grafana.Count -ne 1){throw 'Expected one internal Grafana Service on port 80.'}
$argo=(Invoke-Kubectl @('get','service','argocd-server','-n','argocd','-o','json') | Out-String) | ConvertFrom-Json
if($argo.spec.type -ne 'ClusterIP' -or @($argo.spec.ports | Where-Object {$_.port -eq 443}).Count -ne 1){throw 'Unexpected Argo CD Service; stop before opening tunnels.'}
$targets=@(
    @{Name='argocd';Namespace='argocd';Service='argocd-server';Port=8443;Remote=443;Url='https://localhost:8443'},
    @{Name='grafana';Namespace='monitoring';Service=$grafana[0].metadata.name;Port=3000;Remote=80;Url='http://127.0.0.1:3000'},
    @{Name='prometheus';Namespace='monitoring';Service=$prometheus.metadata.name;Port=9090;Remote=9090;Url='http://127.0.0.1:9090'}
)
foreach($target in $targets){if(Get-NetTCPConnection -State Listen -LocalPort $target.Port -ErrorAction SilentlyContinue){throw "Local port $($target.Port) is already in use. No existing process was stopped."}}
New-Item -ItemType Directory -Path $report -Force | Out-Null
$processes=[System.Collections.Generic.List[object]]::new()
try{
    foreach($target in $targets){
        $outLog=Join-Path $report ($target.Name + '-out.log')
        $errLog=Join-Path $report ($target.Name + '-error.log')
        $process=Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n',$target.Namespace,'port-forward',('service/' + $target.Service),($target.Port.ToString() + ':' + $target.Remote.ToString()),'--address=127.0.0.1') -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        $processes.Add($process)
        $ready=$false
        for($attempt=0;$attempt -lt 20;$attempt++){
            if($process.HasExited){throw "The $($target.Name) tunnel stopped. See $errLog"}
            if((Test-Path $outLog) -and (Get-Content $outLog -Raw) -match 'Forwarding from'){$ready=$true;break}
            Start-Sleep -Seconds 1
        }
        if(-not $ready){throw "The $($target.Name) tunnel was not ready."}
        Write-Host "[READY] $($target.Name): $($target.Url)"
    }
    Write-Host 'Keep this terminal open. Ctrl+C closes only these three owned tunnels.'
    Write-Host 'Argo CD uses its existing internal TLS certificate; this script does not change certificate trust or validation.'
    Write-Host 'Grafana credentials remain in .validation\private-runtime\monitoring-users.json. No passwords are displayed.'
    while($true){
        foreach($process in $processes){if($process.HasExited){throw 'A dashboard tunnel exited. All owned tunnels will be closed.'}}
        Start-Sleep -Seconds 2
    }
}finally{
    foreach($process in $processes){if(-not $process.HasExited){Stop-Process -Id $process.Id -ErrorAction SilentlyContinue}}
}
