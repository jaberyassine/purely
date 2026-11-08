[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$source = Join-Path $project 'deploy-support\certbot'
$report = Join-Path $project '.validation\frontend-tls'
$private = Join-Path $project '.validation\private-runtime'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$registry = 'purelyys71154f86.azurecr.io'
$registryName = 'purelyys71154f86'
$subscription = '71154f86-51d1-45c8-8ace-4f861544bddd'
$managedGroup = 'MC_purely-demo-rg_purely-demo-aks_eastus'
$label = 'purely-demo-71154f86'
$namespace = 'frontend'
$docker = (Get-Command docker.exe -CommandType Application | Select-Object -First 1).Path
$azure = (Get-Command az.cmd -CommandType Application | Select-Object -First 1).Path
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
$roots = 'C:\Program Files\Git\mingw64\etc\ssl\cert.pem'
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
New-Item -ItemType Directory -Path $report -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $private 'database-users.json'))) { throw 'The database/bootstrap private directory is required.' }
if (-not (Test-Path -LiteralPath $roots)) { throw 'The Git OpenSSL public CA bundle was not found. Do not disable certificate verification.' }
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if (-not $?) { throw 'The dedicated AKS connection check failed.' }
$deployments = ((Invoke-Kubectl @('get','deployments','-A','-o','json') | Out-String) | ConvertFrom-Json).items
if (@($deployments | Where-Object { $_.metadata.namespace -eq $namespace -and $_.metadata.name -eq 'frontend' }).Count -gt 0) { throw 'The frontend is already deployed. Do not replace its service selector for certificate bootstrap.' }
$imageRef = Publish-ScannedRuntimeImage -Repository 'certbot-demo' -Source $source -Report $report
Apply-Object @{apiVersion='v1';kind='Namespace';metadata=@{name=$namespace;labels=@{'purely.io/runtime'='demo-v1'}}}
$existing = (Invoke-Kubectl @('get','service','frontend','-n',$namespace,'--ignore-not-found','-o','jsonpath={.metadata.name}:{.metadata.labels.purely\.io/bootstrap}') | Out-String).Trim()
if ($existing -and $existing -ne ':' -and $existing -ne 'frontend:tls-acme-v1') { throw 'An independently managed frontend service exists.' }
$service = @{apiVersion='v1';kind='Service';metadata=@{name='frontend';namespace=$namespace;labels=@{'purely.io/bootstrap'='tls-acme-v1'};annotations=@{'service.beta.kubernetes.io/azure-dns-label-name'=$label}};spec=@{type='LoadBalancer';selector=@{app='purely-acme-bootstrap'};ports=@(@{name='http-acme';port=80;targetPort=8080;protocol='TCP'})}}
Write-Host '[DNS] Reserving the frontend LoadBalancer and Azure DNS label; only the certificate challenge will use port 80.'
Apply-Object $service
$address = $null
for ($attempt=0;$attempt -lt 60;$attempt++) {
    $svc = ((Invoke-Kubectl @('get','service','frontend','-n',$namespace,'-o','json') | Out-String) | ConvertFrom-Json)
    $entries = @($svc.status.loadBalancer.ingress | Where-Object { $_ })
    $address = if ($entries.Count -gt 0) { [string]$entries[0].ip } else { '' }
    if ($address -match '^\d{1,3}(\.\d{1,3}){3}$') { break }
    Start-Sleep -Seconds 5
}
if ($address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'The public IP was not assigned. Review the Service events before retrying.' }
$query = "[?ipAddress=='$address'].dnsSettings.fqdn | [0]"
for ($attempt=0;$attempt -lt 20;$attempt++) {
    $domain = (Invoke-Native $azure @('network','public-ip','list','--resource-group',$managedGroup,'--subscription',$subscription,'--query',$query,'-o','tsv','--only-show-errors') | Out-String).Trim().ToLowerInvariant()
    if ($domain) { break }
    Start-Sleep -Seconds 3
}
if ($domain -notmatch '^purely-demo-71154f86(\.[a-z0-9-]+)?\.eastus\.cloudapp\.azure\.com$') { throw "Unexpected Azure DNS name: $domain" }
$resolved = $false
for ($attempt=0;$attempt -lt 40;$attempt++) {
    try { $resolved = @([Net.Dns]::GetHostAddresses($domain) | Where-Object { $_.IPAddressToString -eq $address }).Count -gt 0 } catch { $resolved = $false }
    if ($resolved) { break }
    Start-Sleep -Seconds 5
}
if (-not $resolved) { throw 'The Azure DNS name does not yet resolve to the frontend IP. Retry after propagation.' }
@{Domain=$domain;IP=$address;Label=$label;Service='frontend/frontend'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $report 'endpoint.json') -Encoding ASCII
Write-Host "[PASS] Azure DNS resolves: $domain -> $address"
$fullchainPath = Join-Path $private 'frontend-fullchain.pem'
$keyPath = Join-Path $private 'frontend.key'
$cached = $false
if ((Test-Path -LiteralPath $fullchainPath) -and (Test-Path -LiteralPath $keyPath)) {
    $ErrorActionPreference = 'Continue'
    & $openssl verify -CAfile $roots -untrusted $fullchainPath -verify_hostname $domain $fullchainPath *> (Join-Path $report 'cached-certificate.log')
    $trusted = $LASTEXITCODE -eq 0
    & $openssl x509 -checkend 604800 -noout -in $fullchainPath *>> (Join-Path $report 'cached-certificate.log')
    $cached = $trusted -and $LASTEXITCODE -eq 0
    $ErrorActionPreference = 'Stop'
}
$jobName = 'purely-certificate-bootstrap'
if (-not $cached) {
    $oldJob = (Invoke-Kubectl @('get','job',$jobName,'-n',$namespace,'--ignore-not-found','-o','jsonpath={.metadata.name}:{.metadata.labels.purely\.io/bootstrap}') | Out-String).Trim()
    if ($oldJob -and $oldJob -ne ':' -and $oldJob -ne "${jobName}:tls-acme-v1") { throw 'An independently managed certificate job exists.' }
    if ($oldJob -and $oldJob -ne ':') { Invoke-Kubectl @('delete','job',$jobName,'-n',$namespace,'--wait=true','--timeout=60s') | Out-Host }
    $container = @{name='certbot';image=$imageRef;command=@('/bin/sh','/opt/purely/issue.sh');env=@(@{name='DOMAIN';value=$domain},@{name='HOME';value='/tmp'});ports=@(@{name='http';containerPort=8080});securityContext=@{allowPrivilegeEscalation=$false;readOnlyRootFilesystem=$true;capabilities=@{drop=@('ALL')}};resources=@{requests=@{cpu='50m';memory='128Mi'};limits=@{cpu='500m';memory='384Mi'}};readinessProbe=@{tcpSocket=@{port=8080};periodSeconds=2};volumeMounts=@(@{name='certs';mountPath='/certs'},@{name='work';mountPath='/work'},@{name='logs';mountPath='/logs'},@{name='tmp';mountPath='/tmp'})}
    $volumes = @('certs','work','logs','tmp' | ForEach-Object { @{name=$_;emptyDir=@{sizeLimit='64Mi'}} })
    $podSpec = @{restartPolicy='Never';automountServiceAccountToken=$false;securityContext=@{runAsNonRoot=$true;runAsUser=10001;runAsGroup=10001;fsGroup=10001;seccompProfile=@{type='RuntimeDefault'}};containers=@($container);volumes=$volumes}
    Apply-Object @{apiVersion='batch/v1';kind='Job';metadata=@{name=$jobName;namespace=$namespace;labels=@{'purely.io/bootstrap'='tls-acme-v1'}};spec=@{backoffLimit=0;activeDeadlineSeconds=2400;template=@{metadata=@{labels=@{app='purely-acme-bootstrap'}};spec=$podSpec}}}
    $pod = $null
    for ($attempt=0;$attempt -lt 30;$attempt++) {
        $pods = @(((Invoke-Kubectl @('get','pods','-l',('job-name=' + $jobName),'-n',$namespace,'-o','json') | Out-String) | ConvertFrom-Json).items)
        if ($pods.Count -gt 0) { $pod=$pods[0].metadata.name; break }
        Start-Sleep -Seconds 2
    }
    if (-not $pod) { throw 'The certificate Job did not create a pod.' }
    Invoke-Kubectl @('wait','--for=condition=Ready',('pod/' + $pod),'-n',$namespace,'--timeout=180s') | Out-Host
    $issued = $false
    Write-Host '[CERTIFICATE] First validate HTTP-01 with the staging CA, then request the trusted production certificate.'
    for ($attempt=0;$attempt -lt 120;$attempt++) {
        $state = ((Invoke-Kubectl @('get','pod',$pod,'-n',$namespace,'-o','json') | Out-String) | ConvertFrom-Json)
        $logs = Invoke-Kubectl @('logs',$pod,'-n',$namespace,'--tail=40') | Out-String
        if ($logs -match 'PURELY_CERTIFICATE_READY') { $issued=$true; break }
        if ($state.status.phase -eq 'Failed') { $logs | Out-Host; throw 'Certificate issuance failed. No frontend application was deployed.' }
        Start-Sleep -Seconds 5
    }
    if (-not $issued) { $logs | Out-Host; throw 'Certificate issuance did not finish. Review the bootstrap Job.' }
    # Capture private key output in memory only; never print it or include it in logs.
    $chain = ((Invoke-Kubectl @('exec',$pod,'-n',$namespace,'--','cat',("/certs/live/$domain/fullchain.pem"))) -join "`n") + "`n"
    $key = ((Invoke-Kubectl @('exec',$pod,'-n',$namespace,'--','cat',("/certs/live/$domain/privkey.pem"))) -join "`n") + "`n"
    if ($chain -notmatch 'BEGIN CERTIFICATE' -or $key -notmatch 'BEGIN (RSA )?PRIVATE KEY') { throw 'Certificate files were not returned in PEM format.' }
    [IO.File]::WriteAllText($fullchainPath,$chain,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($keyPath,$key,[Text.Encoding]::ASCII)
    $logs | Set-Content -LiteralPath (Join-Path $report 'issuance.log') -Encoding ASCII
}
Invoke-Native $openssl @('verify','-CAfile',$roots,'-untrusted',$fullchainPath,'-verify_hostname',$domain,$fullchainPath) | Out-Host
$certificatePublicKey = (Invoke-Native $openssl @('x509','-in',$fullchainPath,'-pubkey','-noout') | Out-String) -replace '\s',''
$privatePublicKey = (Invoke-Native $openssl @('pkey','-in',$keyPath,'-pubout') | Out-String) -replace '\s',''
if ($certificatePublicKey -ne $privatePublicKey) { throw 'The certificate and private key do not match.' }
Invoke-Native $openssl @('x509','-in',$fullchainPath,'-noout','-dates','-subject','-issuer') | Tee-Object -FilePath (Join-Path $report 'certificate-summary.txt') | Out-Host
$current = (Invoke-Kubectl @('get','secret','purely-tls','-n',$namespace,'--ignore-not-found','-o','jsonpath={.metadata.name}:{.metadata.labels.purely\.io/bootstrap}') | Out-String).Trim()
if ($current -and $current -ne ':' -and $current -ne 'purely-tls:runtime-v1') { throw 'An independently managed frontend TLS Secret exists.' }
Apply-Object @{apiVersion='v1';kind='Secret';type='kubernetes.io/tls';metadata=@{name='purely-tls';namespace=$namespace;labels=@{'purely.io/bootstrap'='runtime-v1'}};data=@{'tls.crt'=[Convert]::ToBase64String([IO.File]::ReadAllBytes($fullchainPath));'tls.key'=[Convert]::ToBase64String([IO.File]::ReadAllBytes($keyPath))}}
Invoke-Kubectl @('delete','job',$jobName,'-n',$namespace,'--ignore-not-found','--wait=true','--timeout=60s') | Out-Host
Write-Host "[PASS] Trusted HTTPS certificate prepared for https://$domain"
Write-Host "Public endpoint report: $report\endpoint.json"
Write-Host 'The application is not deployed yet. Its GitOps Service will reuse this IP and DNS label on port 443.'
Write-Host 'This temporary demo uses a one-time certificate issuance. Keep its expiry within the demo lifetime.'
