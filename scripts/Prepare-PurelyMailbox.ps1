[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$source = Join-Path $project 'deploy-support\mailpit'
$chart = Join-Path $project 'k8s\data\mailpit'
$report = Join-Path $project '.validation\mailbox'
$private = Join-Path $project '.validation\private-runtime'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$registry = 'purelyys71154f86.azurecr.io'
$registryName = 'purelyys71154f86'
$subscription = '71154f86-51d1-45c8-8ace-4f861544bddd'
$namespace = 'purely-data'
$docker = (Get-Command docker.exe -CommandType Application | Select-Object -First 1).Path
$azure = (Get-Command az.cmd -CommandType Application | Select-Object -First 1).Path
$helm = (Get-Command helm.exe -CommandType Application | Select-Object -First 1).Path
$python = (Get-Command python.exe -CommandType Application | Select-Object -First 1).Path
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
. (Join-Path $PSScriptRoot 'runtime\Runtime-Helpers.ps1')
New-Item -ItemType Directory -Path $report -Force | Out-Null
foreach ($file in @('ca.crt','ca.key','truststore.p12','database-users.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $private $file))) { throw 'Complete the database bootstrap first. Existing internal CA files are required.' }
}
& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if (-not $?) { throw 'The dedicated AKS connection check failed.' }
$database = (Invoke-Kubectl @('get','statefulset','mongodb','-n',$namespace,'-o','json') | Out-String) | ConvertFrom-Json
if ($database.status.readyReplicas -ne 1) { throw 'The database is not Ready. Review it first.' }
$imageRef = Publish-ScannedRuntimeImage -Repository 'mailpit-demo' -Source $source -Report $report
$mailboxPath = Join-Path $private 'mailbox-users.json'
if (-not (Test-Path -LiteralPath $mailboxPath)) {
    $existing = (Invoke-Kubectl @('get','statefulset','mailpit','-n',$namespace,'--ignore-not-found','-o','name') | Out-String).Trim()
    if ($existing) { throw 'An existing mailbox has no matching credential backup. Do not replace its credentials.' }
    @{smtpUser='purely-demo@example.invalid';smtpPassword=(New-HexPassword);uiUser='demo-admin';uiPassword=(New-HexPassword);subscription=$subscription} | ConvertTo-Json | Set-Content -LiteralPath $mailboxPath -Encoding ASCII
}
$settings = Get-Content -LiteralPath $mailboxPath -Raw | ConvertFrom-Json
if ($settings.subscription -ne $subscription) { throw 'Unexpected mailbox configuration.' }
$certificate = Join-Path $private 'mailpit.crt'
$key = Join-Path $private 'mailpit.key'
if (-not (Test-Path -LiteralPath $certificate)) {
    $csr = Join-Path $private 'mailpit.csr'
    $extensions = Join-Path $private 'mailpit.ext'
    @('basicConstraints=critical,CA:FALSE','keyUsage=critical,digitalSignature,keyEncipherment','extendedKeyUsage=serverAuth','subjectAltName=DNS:mailpit.purely-data.svc.cluster.local,DNS:mailpit.purely-data.svc,DNS:mailpit.purely-data,DNS:mailpit,DNS:localhost,IP:127.0.0.1') | Set-Content -LiteralPath $extensions -Encoding ASCII
    Invoke-Native $openssl @('req','-new','-newkey','rsa:3072','-nodes','-subj','/CN=mailpit.purely-data.svc.cluster.local','-keyout',$key,'-out',$csr) *> (Join-Path $report 'pki.log')
    Invoke-Native $openssl @('x509','-req','-in',$csr,'-CA',(Join-Path $private 'ca.crt'),'-CAkey',(Join-Path $private 'ca.key'),'-CAcreateserial','-days','14','-sha256','-extfile',$extensions,'-out',$certificate) *>> (Join-Path $report 'pki.log')
}
Invoke-Native $openssl @('verify','-CAfile',(Join-Path $private 'ca.crt'),'-verify_hostname','mailpit.purely-data.svc.cluster.local',$certificate) | Out-Host
Invoke-Native $openssl @('x509','-checkend','86400','-noout','-in',$certificate) | Out-Null
Apply-Secret $namespace 'mailpit-tls' @{'tls.crt'=[IO.File]::ReadAllBytes($certificate);'tls.key'=[IO.File]::ReadAllBytes($key)}
Apply-Secret $namespace 'mailpit-auth' @{'smtp-auth'=($settings.smtpUser + ':' + $settings.smtpPassword);'ui-auth'=($settings.uiUser + ':' + $settings.uiPassword)}
Apply-Object @{apiVersion='v1';kind='Namespace';metadata=@{name='notification-service';labels=@{'purely.io/runtime'='demo-v1'}}}
Apply-Secret 'notification-service' 'smtp-secret' @{'smtp-host'='mailpit.purely-data.svc.cluster.local';'smtp-username'=$settings.smtpUser;'smtp-password'=$settings.smtpPassword}
Apply-Secret 'notification-service' 'runtime-trust' @{'truststore.p12'=[IO.File]::ReadAllBytes((Join-Path $private 'truststore.p12'));'ca.crt'=[IO.File]::ReadAllBytes((Join-Path $private 'ca.crt'))}
Invoke-Native $helm @('lint',$chart,'--strict','--set-string',("image=$imageRef")) | Out-Host
Invoke-Native $helm @('template','mailpit-demo',$chart,'--namespace',$namespace,'--set-string',("image=$imageRef")) | Set-Content -LiteralPath (Join-Path $report 'rendered.yaml') -Encoding ASCII
Write-Host '[DEPLOY] Internal authenticated mailbox with required STARTTLS and HTTPS; external relay is not configured.'
Invoke-Native $helm @('upgrade','--install','mailpit-demo',$chart,'--namespace',$namespace,'--kubeconfig',$config,'--kube-context','purely-demo','--set-string',("image=$imageRef"),'--wait','--timeout','5m','--history-max','3') | Out-Host

# The test reaches only loopback-bound forwards, validates the private CA, and reads credentials from the protected directory.
foreach ($port in @(11025,18025)) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($listener) { throw "Local test port $port is already in use. No existing process was stopped." }
}
$outLog = Join-Path $report 'port-forward-out.log'
$errLog = Join-Path $report 'port-forward-error.log'
$forward = $null
try {
    $forward = Start-Process -FilePath $kubectl -ArgumentList @("--kubeconfig=$config",'--context=purely-demo','-n',$namespace,'port-forward','service/mailpit','11025:587','18025:8025','--address=127.0.0.1') -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $ready = $false
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        if ($forward.HasExited) { throw "The owned port-forward process exited. See $errLog" }
        if ((Test-Path -LiteralPath $outLog) -and (Get-Content -LiteralPath $outLog -Raw) -match '18025') { $ready=$true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'The mailbox test port forwards were not ready.' }
    Invoke-Native $python @((Join-Path $source 'verify-mail.py'),$private) | Tee-Object -FilePath (Join-Path $report 'verification.log') | Out-Host
} finally {
    if ($forward -and -not $forward.HasExited) { Stop-Process -Id $forward.Id -ErrorAction SilentlyContinue }
}
Invoke-Kubectl @('get','pods,pvc,services','-n',$namespace) | Out-Host
Write-Host '[PASS] Internal SMTP STARTTLS, server certificate, authentication, rejected bad credentials and captured mail verified.'
Write-Host "Reports: $report"
Write-Host 'Demo mail stays inside Mailpit. No real recipient was contacted; no application rollout was performed.'
