[CmdletBinding()]
param(
    [ValidateRange(30,900)][int]$TimeoutSeconds = 360,
    [switch]$IncludeIntegration
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runId = [Guid]::NewGuid().ToString('N').Substring(0,12)
$runDirectory = Join-Path $projectRoot ('.validation\runtime\' + $runId)
$tlsDirectory = Join-Path $runDirectory 'tls'
New-Item -ItemType Directory -Path $tlsDirectory -Force | Out-Null
$commandLog = Join-Path $runDirectory 'commands.log'
$results = [System.Collections.Generic.List[object]]::new()
$ownedContainers = [System.Collections.Generic.List[string]]::new()
$ownedNetwork = $null
$failureCheck = 'runtime-smoke'
function Find-Application {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.Path }
    }
    throw ('Required application not found: ' + ($Candidates -join ', '))
}
function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    & $Executable @Arguments 2>> $commandLog
    $nativeExitCode = $LASTEXITCODE
    if ($nativeExitCode -ne 0) {
        $failure = [Exception]::new("$Executable exited with code $nativeExitCode; see $commandLog")
        $failure.Data['NativeExitCode'] = $nativeExitCode
        throw $failure
    }
}
function Add-Result {
    param([string]$Check,[string]$Status,[string]$Details)
    $results.Add([pscustomobject]@{Check=$Check;Status=$Status;Details=$Details})
    Write-Host "[$Status] $Check - $Details"
}
function New-TestCertificate {
    param([string]$Directory,[ValidatePattern('^http://127\.0\.0\.1:\d+/ca\.crl$')][string]$CrlUri)
    $caDirectory = Join-Path $Directory 'ca'
    $serverDirectory = Join-Path $Directory 'tls'
    $crlDirectory = Join-Path $Directory 'crl'
    $newCertificates = Join-Path $caDirectory 'issued'
    New-Item -ItemType Directory -Path $caDirectory,$serverDirectory,$crlDirectory,$newCertificates -Force | Out-Null
    $configuration = Join-Path $Directory 'openssl-test.cnf'
    $rootKey = Join-Path $caDirectory 'ca.key'
    $rootCertificate = Join-Path $caDirectory 'ca.crt'
    $database = Join-Path $caDirectory 'index.txt'
    $serial = Join-Path $caDirectory 'serial'
    $crlNumber = Join-Path $caDirectory 'crlnumber'
    [IO.File]::WriteAllText($database,'',[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($serial,"1000`n",[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($crlNumber,"1000`n",[Text.Encoding]::ASCII)
    $configText = @"
[req]
prompt = no
distinguished_name = dn
[dn]
CN = localhost
[ca]
default_ca = local_ca
[local_ca]
database = "$($database.Replace('\','/'))"
new_certs_dir = "$($newCertificates.Replace('\','/'))"
certificate = "$($rootCertificate.Replace('\','/'))"
private_key = "$($rootKey.Replace('\','/'))"
serial = "$($serial.Replace('\','/'))"
crlnumber = "$($crlNumber.Replace('\','/'))"
default_md = sha256
default_days = 2
default_crl_days = 1
policy = policy_any
crl_extensions = crl_ext
[policy_any]
commonName = supplied
[ca_cert]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
crlDistributionPoints = URI:$CrlUri
[server]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1
authorityKeyIdentifier = keyid,issuer
crlDistributionPoints = URI:$CrlUri
[crl_ext]
authorityKeyIdentifier = keyid:always
"@
    [IO.File]::WriteAllText($configuration,$configText,[Text.Encoding]::ASCII)
    $serverKey = Join-Path $serverDirectory 'tls.key'
    $serverCertificate = Join-Path $serverDirectory 'tls.crt'
    $request = Join-Path $Directory 'server.csr'
    Invoke-Native $openssl @('req','-x509','-newkey','rsa:2048','-sha256','-nodes','-days','2',
        '-config',$configuration,'-extensions','ca_cert','-keyout',$rootKey,'-out',$rootCertificate,
        '-subj',('/CN=Purely Local Test CA ' + [Guid]::NewGuid().ToString('N'))) | Out-Null
    Invoke-Native $openssl @('req','-new','-newkey','rsa:2048','-sha256','-nodes',
        '-config',$configuration,'-keyout',$serverKey,'-out',$request,'-subj','/CN=localhost') | Out-Null
    Invoke-Native $openssl @('x509','-req','-in',$request,'-CA',$rootCertificate,'-CAkey',$rootKey,
        '-CAcreateserial','-out',$serverCertificate,'-days','2','-sha256','-extfile',$configuration,
        '-extensions','server') | Out-Null
    $crlPem = Join-Path $caDirectory 'ca-crl.pem'
    $crlDer = Join-Path $crlDirectory 'ca.crl'
    Invoke-Native $openssl @('ca','-gencrl','-batch','-config',$configuration,'-cert',$rootCertificate,
        '-keyfile',$rootKey,'-out',$crlPem) | Out-Null
    Invoke-Native $openssl @('crl','-in',$crlPem,'-outform','DER','-out',$crlDer) | Out-Null
    Invoke-Native $openssl @('verify','-CAfile',$rootCertificate,'-CRLfile',$crlPem,'-crl_check',
        '-purpose','sslserver','-verify_ip','127.0.0.1',$serverCertificate) | Out-Null
    return [pscustomobject]@{RootCertificate=$rootCertificate;TlsDirectory=$serverDirectory;CrlDirectory=$crlDirectory}
}
function Get-FreeLoopbackPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    try { $listener.Start(); return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}
function Get-PublishedUri {
    param([string]$ContainerId,[int]$ContainerPort,[string]$Scheme='http')
    $endpoint = (Invoke-Native $docker @('port',$ContainerId,"$ContainerPort/tcp") | Out-String).Trim()
    if ($endpoint -notmatch '^127\.0\.0\.1:\d+$') { throw "Unexpected published endpoint: $endpoint" }
    return "${Scheme}://$endpoint"
}
function Start-OwnedContainer {
    param([string]$Name,[string]$Image,[string[]]$Options)
    $imageId = (Invoke-Native $docker @('image','inspect','--format','{{.Id}}',$Image) | Out-String).Trim()
    if ($imageId -notmatch '^sha256:[a-f0-9]{64}$') { throw "Invalid local image ID for $Image" }
    if ($Image -notmatch '^purely-local/([^:]+):validation$') { throw 'Unexpected application image reference.' }
    $service = $Matches[1]
    $scanned = @($scanSummary | Where-Object Service -eq $service)
    if ($scanned.Count -ne 1 -or $scanned[0].Status -ne 'PASS' -or $scanned[0].ImageId -ne $imageId) {
        throw "The current $service image does not match a passing scan. Rescan it first."
    }
    $arguments = @('create','--name',$Name,'--network',$ownedNetwork,'--pull','never',
        '--read-only','--cap-drop','ALL','--security-opt','no-new-privileges') + $Options + @($imageId)
    $containerId = (Invoke-Native $docker $arguments | Out-String).Trim()
    if ($containerId -notmatch '^[a-f0-9]{64}$') { throw 'Docker did not return a valid created container ID.' }
    $ownedContainers.Add($containerId)
    Invoke-Native $docker @('start',$containerId) | Out-Null
    Add-Result ($Name + '-image') 'PASS' $imageId
    return $containerId
}
function Wait-Healthy {
    param([string]$Name,[string]$Uri)
    $body = Join-Path $runDirectory ($Name + '-health.json')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastNotice = 0
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            Invoke-Native $curl @('--silent','--show-error','--fail','--connect-timeout','2','--max-time','5',
                '--output',$body,($Uri + '/actuator/health/readiness')) | Out-Null
            $health = Get-Content -LiteralPath $body -Raw | ConvertFrom-Json
            if ($health.status -eq 'UP') { Add-Result ($Name + '-readiness') 'PASS' 'UP'; return }
        } catch { }
        if (($clock.Elapsed.TotalSeconds - $lastNotice) -ge 15) {
            Write-Host "[WAIT] $Name readiness: $([int]$clock.Elapsed.TotalSeconds)s"
            $lastNotice = $clock.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    throw "$Name did not become healthy within $TimeoutSeconds seconds."
}
function Test-Metrics {
    param([string]$Name,[string]$Uri)
    $body = Join-Path $runDirectory ($Name + '-metrics.txt')
    Invoke-Native $curl @('--silent','--show-error','--fail','--max-time','10','--output',$body,($Uri + '/actuator/prometheus')) | Out-Null
    if ((Get-Content -LiteralPath $body -Raw) -notmatch '(?m)^# HELP ') { throw "$Name did not return Prometheus metrics." }
    Add-Result ($Name + '-metrics') 'PASS' 'Prometheus response received'
}
try {
    $docker = Find-Application @('docker.exe','docker')
    $curl = Find-Application @('curl.exe')
    $openssl = Find-Application @('openssl.exe','C:\Program Files\Git\usr\bin\openssl.exe')
    Invoke-Native $docker @('info','--format','{{.ServerVersion}}') | Out-Null
    Add-Result 'docker-engine' 'PASS' 'Connected'
    $scanSummary = Import-Csv -LiteralPath (Join-Path $projectRoot '.validation\trivy\scan-summary.csv')

    # Adapt only this copy to Docker DNS and the container's direct port.
    # In AKS the gateway Service maps port 80 to container port 8081.
    $originalNginx = Join-Path $projectRoot 'frontend\nginx.conf'
    $localNginx = Join-Path $runDirectory 'nginx.conf'
    $nginxText = [IO.File]::ReadAllText($originalNginx)
    if (-not $nginxText.Contains('resolver 10.1.0.10')) { throw 'Review the local DNS adaptation after changing nginx.conf.' }
    $nginxText = $nginxText.Replace('resolver 10.1.0.10','resolver 127.0.0.11')
    $gatewaySetting = 'set $gateway api-gateway.api-gateway.svc.cluster.local;'
    if (-not $nginxText.Contains($gatewaySetting)) { throw 'Review the local gateway port adaptation after changing nginx.conf.' }
    $nginxText = $nginxText.Replace($gatewaySetting, 'set $gateway api-gateway.api-gateway.svc.cluster.local:8081;')
    if (-not $nginxText.Contains('  location = /healthz')) { throw 'Review the local CRL location after changing nginx.conf.' }
    $nginxText = $nginxText.Replace('  location = /healthz',
        '  location = /ca.crl { root /etc/nginx/crl; default_type application/pkix-crl; }' + "`n" + '  location = /healthz')
    [IO.File]::WriteAllText($localNginx,$nginxText,[Text.Encoding]::ASCII)

    # Host-side curl/readiness checks need published loopback ports. An internal
    # network did not publish these ports on the tested Docker Desktop host.
    # This dedicated bridge is not an outbound traffic firewall.
    $networkOptions = @('network','create','--driver','bridge',
        '--opt','com.docker.network.bridge.host_binding_ipv4=127.0.0.1')
    $networkId = (Invoke-Native $docker ($networkOptions + @('purely-smoke-' + $runId)) | Out-String).Trim()
    if ($networkId -notmatch '^[a-f0-9]{64}$') { throw 'Docker did not return a valid network ID.' }
    $ownedNetwork = $networkId
    $javaOptions = @('--user','10001:10001','--memory','768m','--cpus','1',
        '--tmpfs','/tmp:rw,nosuid,size=128m,uid=10001,gid=10001')
    $registry = Start-OwnedContainer ('purely-registry-' + $runId) 'purely-local/service-registry:validation' (
        $javaOptions + @('--network-alias','service-registry.service-registry.svc.cluster.local',
        '--publish','127.0.0.1::8761'))
    $registryUri = Get-PublishedUri $registry 8761
    Wait-Healthy 'registry' $registryUri
    Test-Metrics 'registry' $registryUri

    $gateway = Start-OwnedContainer ('purely-gateway-' + $runId) 'purely-local/api-gateway:validation' (
        $javaOptions + @('--network-alias','api-gateway.api-gateway.svc.cluster.local',
        '--publish','127.0.0.1::8081'))
    $gatewayUri = Get-PublishedUri $gateway 8081
    Wait-Healthy 'gateway' $gatewayUri
    Test-Metrics 'gateway' $gatewayUri

    $crlPort = Get-FreeLoopbackPort
    $crlUri = "http://127.0.0.1:${crlPort}/ca.crl"
    Write-Host '[PREPARE] Creating a localhost certificate and signed revocation list.'
    $testCertificate = New-TestCertificate $runDirectory $crlUri
    $certificate = $testCertificate.RootCertificate
    $tlsDirectory = $testCertificate.TlsDirectory
    $crlDirectory = $testCertificate.CrlDirectory
    Add-Result 'test-certificate' 'PASS' 'Certificate, identity and signed revocation list verified'

    $frontend = Start-OwnedContainer ('purely-frontend-' + $runId) 'purely-local/frontend:validation' @(
        '--user','101:101','--memory','128m','--cpus','0.25','--publish','127.0.0.1::8443',
        '--publish',"127.0.0.1:${crlPort}:8080",
        '--tmpfs','/var/cache/nginx:rw,nosuid,size=32m,uid=101,gid=101',
        '--tmpfs','/var/run:rw,nosuid,size=4m,uid=101,gid=101',
        '--tmpfs','/tmp:rw,nosuid,size=8m,uid=101,gid=101',
        '--mount',"type=bind,source=$tlsDirectory,target=/etc/nginx/tls,readonly",
        '--mount',"type=bind,source=$crlDirectory,target=/etc/nginx/crl,readonly",
        '--mount',"type=bind,source=$localNginx,target=/etc/nginx/conf.d/default.conf,readonly")
    $frontendUri = Get-PublishedUri $frontend 8443 'https'
    $downloadedCrl = Join-Path $runDirectory 'downloaded-ca.crl'
    $downloadedPem = Join-Path $runDirectory 'downloaded-ca-crl.pem'
    Invoke-Native $curl @('--silent','--show-error','--fail','--retry','10','--retry-connrefused',
        '--retry-delay','1','--retry-max-time','30','--max-time','5','--output',$downloadedCrl,$crlUri) | Out-Null
    Invoke-Native $openssl @('crl','-inform','DER','-in',$downloadedCrl,'-out',$downloadedPem) | Out-Null
    Invoke-Native $openssl @('verify','-CAfile',$certificate,'-CRLfile',$downloadedPem,'-crl_check',
        '-purpose','sslserver','-verify_ip','127.0.0.1',(Join-Path $tlsDirectory 'tls.crt')) | Out-Null
    Add-Result 'test-crl-http' 'PASS' 'Signed CRL served on localhost and verified'
    $html = Join-Path $runDirectory 'frontend.html'
    $headers = Join-Path $runDirectory 'frontend-headers.txt'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $served = $false
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            Invoke-Native $curl @('--silent','--show-error','--fail','--max-time','5','--cacert',$certificate,
                '--dump-header',$headers,'--output',$html,($frontendUri + '/')) | Out-Null
            $served = $true
            break
        } catch {
            if ($_.Exception.Data['NativeExitCode'] -eq 60) {
                throw "Frontend certificate verification failed; see $commandLog"
            }
            Start-Sleep -Seconds 2
        }
    }
    if (-not $served) { throw 'Frontend HTTPS did not become available.' }
    if ((Get-Content -LiteralPath $html -Raw) -notmatch '<div\s+id="root"') { throw 'Frontend did not serve the SPA entry document.' }
    if ((Get-Content -LiteralPath $headers -Raw) -notmatch '(?im)^X-Content-Type-Options:\s*nosniff') { throw 'Frontend security header is missing.' }
    Add-Result 'frontend-https' 'PASS' 'Certificate verified against the temporary test CA; SPA document served'

    $blockedBody = Join-Path $runDirectory 'blocked-actuator.txt'
    $status = (Invoke-Native $curl @('--silent','--show-error','--max-time','10','--cacert',$certificate,
        '--output',$blockedBody,'--write-out','%{http_code}',($frontendUri + '/product-service/actuator/prometheus')) | Out-String).Trim()
    if ($status -ne '404') { throw "Public actuator route returned $status instead of 404." }
    Add-Result 'public-actuator-blocked' 'PASS' 'HTTP 404'

    $routeBody = Join-Path $runDirectory 'gateway-route.json'
    $status = (Invoke-Native $curl @('--silent','--show-error','--max-time','15','--cacert',$certificate,
        '--header','Accept: application/json','--output',$routeBody,'--write-out','%{http_code}',($frontendUri + '/product-service/product/get/all')) | Out-String).Trim()
    if ($status -ne '503') { throw "Gateway proxy returned HTTP $status; expected 503 for the deliberately absent product service. See $routeBody and container logs." }
    try { $routeResponse = Get-Content -LiteralPath $routeBody -Raw | ConvertFrom-Json }
    catch { throw "Gateway proxy returned HTTP $status with invalid JSON. See $routeBody and container logs." }
    if ($routeResponse.status -ne 503) { throw "Expected gateway JSON status 503 for the deliberately absent product service. See $routeBody." }
    Add-Result 'frontend-gateway-routing' 'PASS' 'Gateway JSON 503 confirms proxy routing to an intentionally absent backend'

    $appsBody = Join-Path $runDirectory 'eureka-apps.json'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $registered = $false
    $lastNotice = 0
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            Invoke-Native $curl @('--silent','--show-error','--fail','--max-time','5','--header','Accept: application/json',
                '--output',$appsBody,($registryUri + '/eureka/apps')) | Out-Null
            $apps = Get-Content -LiteralPath $appsBody -Raw | ConvertFrom-Json
            if (@($apps.applications.application | Where-Object name -eq 'API-GATEWAY').Count -gt 0) { $registered = $true; break }
        } catch { }
        if (($clock.Elapsed.TotalSeconds - $lastNotice) -ge 15) {
            Write-Host "[WAIT] Eureka registration: $([int]$clock.Elapsed.TotalSeconds)s"
            $lastNotice = $clock.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    if (-not $registered) { throw 'Gateway was not registered in Eureka before timeout.' }
    Add-Result 'gateway-discovery' 'PASS' 'API-GATEWAY registered in Eureka'
    if ($IncludeIntegration) {
        $failureCheck = 'business-integration'
        . (Join-Path $PSScriptRoot 'integration-checks.ps1')
        Test-BusinessIntegration
    }
} catch {
    Add-Result $failureCheck 'FAIL' $_.Exception.Message
} finally {
    # Operate only on the exact IDs returned by this run's successful create calls.
    for ($i=$ownedContainers.Count-1; $i -ge 0; $i--) {
        $id = $ownedContainers[$i]
        try {
            Invoke-Native $docker @('logs',$id) > (Join-Path $runDirectory ($id.Substring(0,12) + '.log'))
        } catch {
            Add-Result 'container-logs' 'FAIL' ('Could not capture logs for owned container ' + $id)
        }
        try {
            Invoke-Native $docker @('container','rm','--force',$id) | Out-Null
        } catch {
            Add-Result 'container-cleanup' 'FAIL' ('Could not clean up owned container ' + $id)
        }
    }
    if ($ownedNetwork) {
        try { Invoke-Native $docker @('network','rm',$ownedNetwork) | Out-Null }
        catch { Add-Result 'network-cleanup' 'FAIL' ('Could not remove owned network ' + $ownedNetwork) }
    }
    $csv = Join-Path $runDirectory 'runtime-results.csv'
    $results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Copy-Item -LiteralPath $csv -Destination (Join-Path $projectRoot '.validation\runtime-results.csv') -Force
    $results | Format-Table Check,Status -AutoSize
    Write-Host "Report: $csv"
}
if (@($results | Where-Object Status -ne 'PASS').Count -gt 0) { throw 'Runtime checks failed. Review the run directory and logs.' }
Write-Host 'Runtime smoke checks passed; temporary containers and network were removed.'
