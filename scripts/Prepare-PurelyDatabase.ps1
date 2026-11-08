[CmdletBinding()]
param([string]$WorkspaceRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$project = Join-Path $WorkspaceRoot 'purely-ready'
$source = Join-Path $project 'deploy-support\mongodb'
$chart = Join-Path $project 'k8s\data\mongodb'
$report = Join-Path $project '.validation\database'
$private = Join-Path $project '.validation\private-runtime'
$configPath = Join-Path $private 'database-users.json'
$config = Join-Path $project '.validation\aks\purely-demo.kubeconfig'
$registry = 'purelyys71154f86.azurecr.io'
$registryName = 'purelyys71154f86'
$subscription = '71154f86-51d1-45c8-8ace-4f861544bddd'
$namespace = 'purely-data'
$services = @('auth-service','user-service','product-service','category-service','cart-service','order-service')
$docker = (Get-Command docker.exe -CommandType Application | Select-Object -First 1).Path
$azure = (Get-Command az.cmd -CommandType Application | Select-Object -First 1).Path
$helm = (Get-Command helm.exe -CommandType Application | Select-Object -First 1).Path
$kubectl = if (Test-Path 'C:\kubectl\kubectl.exe') { 'C:\kubectl\kubectl.exe' } else { (Get-Command kubectl.exe -CommandType Application | Select-Object -First 1).Path }
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
$jdk = 'C:\Program Files\Java\jdk-21'
foreach ($path in @($openssl,(Join-Path $jdk 'bin\keytool.exe'),(Join-Path $source 'Dockerfile'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file was not found: $path" }
}
New-Item -ItemType Directory -Path $report -Force | Out-Null
function Invoke-Native {
    param([string]$Executable,[string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $raw = & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $([IO.Path]::GetFileName($Executable)). Review the preceding error." }
    return $raw
}
function Invoke-Kubectl {
    param([string[]]$Arguments)
    Invoke-Native $kubectl (@("--kubeconfig=$config",'--context=purely-demo','--request-timeout=60s') + $Arguments)
}
function Apply-Object {
    param([object]$Object)
    $json = $Object | ConvertTo-Json -Depth 60 -Compress
    $ErrorActionPreference = 'Continue'
    $output = $json | & $kubectl "--kubeconfig=$config" --context=purely-demo --request-timeout=60s apply --server-side --field-manager=purely-runtime -f -
    if ($LASTEXITCODE -ne 0) { throw 'Applying the runtime object failed.' }
    $output | Out-Host
}
function Apply-Secret {
    param([string]$Namespace,[string]$Name,[hashtable]$Values)
    # Read only metadata when deciding whether an existing Secret belongs to this bootstrap.
    $current = (Invoke-Kubectl @('get','secret',$Name,'-n',$Namespace,'--ignore-not-found','-o','jsonpath={.metadata.name}:{.metadata.labels.purely\.io/bootstrap}') | Out-String).Trim()
    if ($current -and $current -ne ':' -and $current -ne "${Name}:runtime-v1") { throw "An independently managed Secret exists: $Namespace/$Name" }
    $encoded = @{}
    foreach ($key in $Values.Keys) {
        $bytes = if ($Values[$key] -is [byte[]]) { $Values[$key] } else { [Text.Encoding]::UTF8.GetBytes([string]$Values[$key]) }
        $encoded[$key] = [Convert]::ToBase64String($bytes)
    }
    Apply-Object @{apiVersion='v1';kind='Secret';type='Opaque';metadata=@{name=$Name;namespace=$Namespace;labels=@{'purely.io/bootstrap'='runtime-v1'}};data=$encoded}
}
function New-HexPassword {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}

& (Join-Path $WorkspaceRoot 'Connect-PurelyAks.ps1')
if (-not $?) { throw 'The dedicated AKS connection check failed.' }
$existing = ((Invoke-Kubectl @('get','statefulsets','-A','-o','json') | Out-String) | ConvertFrom-Json).items
$existingClaims = ((Invoke-Kubectl @('get','pvc','-A','-o','json') | Out-String) | ConvertFrom-Json).items
$databaseExists = @($existing | Where-Object { $_.metadata.namespace -eq $namespace -and $_.metadata.name -eq 'mongodb' }).Count -gt 0
$diskExists = @($existingClaims | Where-Object { $_.metadata.namespace -eq $namespace -and $_.metadata.name -eq 'data-mongodb-0' }).Count -gt 0
if (($databaseExists -or $diskExists) -and -not (Test-Path -LiteralPath $configPath)) {
    throw 'An existing database has no matching local credential backup. Do not generate replacement credentials.'
}

Write-Host '[BUILD] Dedicated non-root database server image; no application images are changed.'
$localImage = 'purely-local/mongodb-demo:bootstrap'
Invoke-Native $docker @('build','--pull','-t',$localImage,$source) *> (Join-Path $report 'build.log')
$imageId = (Invoke-Native $docker @('image','inspect','--format','{{.Id}}',$localImage) | Out-String).Trim()
$input = Join-Path $report 'input'
$cache = Join-Path $project '.validation\trivy\cache'
foreach ($path in @($input,$cache)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
Invoke-Native $docker @('image','save','--output',(Join-Path $input 'mongodb.tar'),$localImage) *> (Join-Path $report 'save.log')
Invoke-Native $docker @('pull','aquasec/trivy:0.76.2') *> (Join-Path $report 'scan.log')
Write-Host '[SCAN] Blocking HIGH/CRITICAL vulnerabilities and secrets before registry publication or deployment.'
Invoke-Native $docker @('run','--rm','--mount',"type=bind,source=$input,target=/input,readonly",'--mount',"type=bind,source=$cache,target=/root/.cache",'--mount',"type=bind,source=$report,target=/reports",'aquasec/trivy:0.76.2','image','--input','/input/mongodb.tar','--scanners','vuln,secret','--severity','HIGH,CRITICAL','--format','json','--output','/reports/trivy.json','--timeout','15m','--exit-code','0') *>> (Join-Path $report 'scan.log')
$scan = Get-Content -LiteralPath (Join-Path $report 'trivy.json') -Raw | ConvertFrom-Json
if ($scan.SchemaVersion -ne 2 -or -not $scan.PSObject.Properties['Results']) { throw 'The scanner did not produce a valid report.' }
$vulnerabilities = @($scan.Results | ForEach-Object { $_.Vulnerabilities } | Where-Object { $_ -and $_.Severity -in @('HIGH','CRITICAL') })
$secrets = @($scan.Results | ForEach-Object { $_.Secrets } | Where-Object { $_ -and $_.Severity -in @('HIGH','CRITICAL') })
$scanRow = [pscustomobject]@{ImageId=$imageId;High=@($vulnerabilities | Where-Object Severity -eq 'HIGH').Count;Critical=@($vulnerabilities | Where-Object Severity -eq 'CRITICAL').Count;Secrets=$secrets.Count}
$scanRow | Export-Csv -LiteralPath (Join-Path $report 'scan-summary.csv') -NoTypeInformation -Encoding UTF8
if ($vulnerabilities.Count -gt 0 -or $secrets.Count -gt 0) { $scanRow | Format-List | Out-Host; throw "Image blocked. Review $report\trivy.json. No database was deployed." }
Write-Host '[PASS] Image scan: zero HIGH/CRITICAL vulnerabilities or secrets.'

$imageRecordPath = Join-Path $report 'image.json'
$imageRecord = if (Test-Path -LiteralPath $imageRecordPath) { Get-Content -LiteralPath $imageRecordPath -Raw | ConvertFrom-Json } else { $null }
if ($imageRecord -and $imageRecord.ImageId -eq $imageId -and $imageRecord.Reference -match '^purelyys71154f86\.azurecr\.io/mongodb-demo@sha256:[a-f0-9]{64}$') {
    $digest = (Invoke-Native $azure @('acr','repository','show','--name',$registryName,'--subscription',$subscription,'--image',('mongodb-demo:' + $imageRecord.Tag),'--query','digest','-o','tsv','--only-show-errors') | Out-String).Trim()
    if ($imageRecord.Reference -ne "$registry/mongodb-demo@$digest") { throw 'The stored registry digest does not match.' }
    $imageRef = $imageRecord.Reference
    Write-Host '[PASS] Reusing the same scanned immutable registry digest.'
} else {
    $tag = 'mongo8-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $remoteImage = "$registry/mongodb-demo:$tag"
    Invoke-Native $azure @('acr','login','--name',$registryName,'--subscription',$subscription,'--only-show-errors') | Out-Host
    Invoke-Native $docker @('tag',$localImage,$remoteImage) | Out-Null
    Invoke-Native $docker @('push',$remoteImage) *> (Join-Path $report 'push.log')
    $digest = (Invoke-Native $azure @('acr','repository','show','--name',$registryName,'--subscription',$subscription,'--image',('mongodb-demo:' + $tag),'--query','digest','-o','tsv','--only-show-errors') | Out-String).Trim()
    if ($digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'An immutable registry digest was not returned.' }
    Invoke-Native $azure @('acr','repository','update','--name',$registryName,'--subscription',$subscription,'--image',('mongodb-demo:' + $tag),'--write-enabled','false','--delete-enabled','false','--only-show-errors') | Out-Null
    $imageRef = "$registry/mongodb-demo@$digest"
    @{ImageId=$imageId;Tag=$tag;Reference=$imageRef} | ConvertTo-Json | Set-Content -LiteralPath $imageRecordPath -Encoding ASCII
}

# Private keys and generated credentials remain in this excluded directory with restricted Windows ACLs.
New-Item -ItemType Directory -Path $private -Force | Out-Null
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Invoke-Native 'icacls.exe' @($private,'/inheritance:r','/grant:r',"*${sid}:(OI)(CI)F",'*S-1-5-18:(OI)(CI)F') | Out-Null
if (-not (Test-Path -LiteralPath $configPath)) {
    $accounts = @($services | ForEach-Object {
        $short = $_.Replace('-service','')
        @{service=$_;database=('purely_' + $short);user=('purely_' + $short);password=(New-HexPassword)}
    })
    $settings = @{subscription=$subscription;admin=@{user='purely_db_admin';password=(New-HexPassword)};services=$accounts;jwtSecret=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes((New-HexPassword)));persistenceToken=(New-HexPassword)}
    $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding ASCII
}
$settings = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($settings.subscription -ne $subscription -or @($settings.services).Count -ne 6) { throw 'Unexpected local runtime configuration.' }
$ca = Join-Path $private 'ca.crt'
$caKey = Join-Path $private 'ca.key'
$serverCert = Join-Path $private 'mongodb.crt'
$serverKey = Join-Path $private 'mongodb.key'
$serverPem = Join-Path $private 'mongodb.pem'
$trust = Join-Path $private 'truststore.p12'
if (-not (Test-Path -LiteralPath $ca)) {
    Invoke-Native $openssl @('req','-x509','-newkey','rsa:3072','-sha256','-days','30','-nodes','-subj','/CN=Purely Demo Internal CA','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign','-keyout',$caKey,'-out',$ca) *> (Join-Path $report 'pki.log')
}
if (-not (Test-Path -LiteralPath $serverCert)) {
    $csr = Join-Path $private 'mongodb.csr'
    $extensions = Join-Path $private 'mongodb.ext'
    @('basicConstraints=critical,CA:FALSE','keyUsage=critical,digitalSignature,keyEncipherment','extendedKeyUsage=serverAuth','subjectAltName=DNS:mongodb.purely-data.svc.cluster.local,DNS:mongodb.purely-data.svc,DNS:mongodb.purely-data,DNS:mongodb,DNS:localhost,IP:127.0.0.1') | Set-Content -LiteralPath $extensions -Encoding ASCII
    Invoke-Native $openssl @('req','-new','-newkey','rsa:3072','-nodes','-subj','/CN=mongodb.purely-data.svc.cluster.local','-keyout',$serverKey,'-out',$csr) *>> (Join-Path $report 'pki.log')
    Invoke-Native $openssl @('x509','-req','-in',$csr,'-CA',$ca,'-CAkey',$caKey,'-CAcreateserial','-days','14','-sha256','-extfile',$extensions,'-out',$serverCert) *>> (Join-Path $report 'pki.log')
    [IO.File]::WriteAllText($serverPem,([IO.File]::ReadAllText($serverKey) + [IO.File]::ReadAllText($serverCert)),[Text.Encoding]::ASCII)
}
Invoke-Native $openssl @('verify','-CAfile',$ca,'-verify_hostname','mongodb.purely-data.svc.cluster.local',$serverCert) | Out-Host
Invoke-Native $openssl @('x509','-checkend','86400','-noout','-in',$serverCert) | Out-Null
if (-not (Test-Path -LiteralPath $trust)) {
    # A truststore contains public CA certificates only. Preserve the standard Java roots too.
    $keytool = Join-Path $jdk 'bin\keytool.exe'
    Invoke-Native $keytool @('-importkeystore','-srckeystore',(Join-Path $jdk 'lib\security\cacerts'),'-srcstorepass','changeit','-destkeystore',$trust,'-deststoretype','PKCS12','-deststorepass','changeit','-noprompt') *> (Join-Path $report 'truststore.log')
    Invoke-Native $keytool @('-importcert','-alias','purely-demo-internal','-file',$ca,'-keystore',$trust,'-storetype','PKCS12','-storepass','changeit','-noprompt') *>> (Join-Path $report 'truststore.log')
}
foreach ($ns in (@($namespace) + $services)) {
    Apply-Object @{apiVersion='v1';kind='Namespace';metadata=@{name=$ns;labels=@{'purely.io/runtime'='demo-v1'}}}
}
Apply-Secret $namespace 'mongodb-tls' @{'ca.crt'=[IO.File]::ReadAllBytes($ca);'server.pem'=[IO.File]::ReadAllBytes($serverPem)}
$bootstrapUsers = $settings | Select-Object admin,services,persistenceToken | ConvertTo-Json -Depth 10 -Compress
Apply-Secret $namespace 'mongodb-bootstrap' @{'users.json'=$bootstrapUsers;'bootstrap.js'=[IO.File]::ReadAllBytes((Join-Path $source 'bootstrap.js'));'verify.js'=[IO.File]::ReadAllBytes((Join-Path $source 'verify.js'));'persistence.js'=[IO.File]::ReadAllBytes((Join-Path $source 'persistence.js'))}
foreach ($account in $settings.services) {
    $uri = 'mongodb://' + $account.user + ':' + $account.password + '@mongodb.purely-data.svc.cluster.local:27017/' + $account.database + '?authSource=' + $account.database + '&tls=true'
    Apply-Secret $account.service 'mongodb-secret' @{uri=$uri}
    Apply-Secret $account.service 'runtime-trust' @{'truststore.p12'=[IO.File]::ReadAllBytes($trust);'ca.crt'=[IO.File]::ReadAllBytes($ca)}
}
Apply-Secret 'auth-service' 'auth-secret' @{'jwt-secret'=$settings.jwtSecret}
Invoke-Native $helm @('lint',$chart,'--strict','--set-string',("image=$imageRef")) | Out-Host
Invoke-Native $helm @('template','mongodb-demo',$chart,'--namespace',$namespace,'--set-string',("image=$imageRef")) | Set-Content -LiteralPath (Join-Path $report 'rendered.yaml') -Encoding ASCII
Write-Host '[DEPLOY] Standalone MongoDB with verified TLS, authentication and a retained 16Gi Azure Disk PVC.'
Invoke-Native $helm @('upgrade','--install','mongodb-demo',$chart,'--namespace',$namespace,'--kubeconfig',$config,'--kube-context','purely-demo','--set-string',("image=$imageRef"),'--wait','--timeout','10m','--history-max','3') | Out-Host
Invoke-Kubectl @('exec','mongodb-0','-n',$namespace,'--','mongosh','--quiet','--tls','--tlsCAFile','/etc/mongodb/tls/ca.crt','--host','localhost','--file','/bootstrap/bootstrap.js') | Out-Host
Invoke-Kubectl @('exec','mongodb-0','-n',$namespace,'--','mongosh','--quiet','--tls','--tlsCAFile','/etc/mongodb/tls/ca.crt','--host','localhost','--file','/bootstrap/verify.js') | Tee-Object -FilePath (Join-Path $report 'accounts-verification.log') | Out-Host
Invoke-Kubectl @('exec','mongodb-0','-n',$namespace,'--','env','PURELY_PERSISTENCE_MODE=write','mongosh','--quiet','--tls','--tlsCAFile','/etc/mongodb/tls/ca.crt','--host','localhost','--file','/bootstrap/persistence.js') | Out-Host
Write-Host '[VERIFY] Restarting only the new database pod to verify persistent data before any application deployment.'
Invoke-Kubectl @('rollout','restart','statefulset/mongodb','-n',$namespace) | Out-Host
Invoke-Kubectl @('rollout','status','statefulset/mongodb','-n',$namespace,'--timeout=300s') | Out-Host
Invoke-Kubectl @('exec','mongodb-0','-n',$namespace,'--','mongosh','--quiet','--tls','--tlsCAFile','/etc/mongodb/tls/ca.crt','--host','localhost','--file','/bootstrap/persistence.js') | Out-Host
$pvcs = ((Invoke-Kubectl @('get','pvc','-n',$namespace,'-o','json') | Out-String) | ConvertFrom-Json).items
$rows = @($pvcs | ForEach-Object { [pscustomobject]@{Name=$_.metadata.name;Status=$_.status.phase;StorageClass=$_.spec.storageClassName;Capacity=$_.status.capacity.storage;Volume=$_.spec.volumeName} })
$rows | Export-Csv -LiteralPath (Join-Path $report 'storage.csv') -NoTypeInformation -Encoding UTF8
if (@($rows | Where-Object { $_.Name -eq 'data-mongodb-0' -and $_.Status -eq 'Bound' -and $_.StorageClass -eq 'managed-csi' }).Count -ne 1) { throw 'The expected Azure Disk claim is not Bound.' }
Invoke-Kubectl @('get','pods,pvc,services','-n',$namespace) | Out-Host
Write-Host '[PASS] MongoDB TLS, six scoped accounts, cross-database denial and persistence after pod restart verified.'
Write-Host "Reports: $report"
Write-Host 'Private runtime credentials and CA keys are retained locally; do not share the private-runtime directory.'
Write-Host 'This is a single-instance temporary demo database. It is not a high-availability production database.'
Write-Host 'No application rollout, SMTP deployment or public frontend exposure was performed.'
