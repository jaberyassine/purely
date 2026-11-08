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


function Publish-ScannedRuntimeImage {
    param([string]$Repository,[string]$Source,[string]$Report)
Write-Host "[BUILD] Dedicated runtime image: $Repository"
$localImage = ("purely-local/" + $Repository + ":bootstrap")
Invoke-Native $docker @('build','--pull','-t',$localImage,$source) *> (Join-Path $report 'build.log')
$imageId = (Invoke-Native $docker @('image','inspect','--format','{{.Id}}',$localImage) | Out-String).Trim()
$input = Join-Path $report 'input'
$cache = Join-Path $project '.validation\trivy\cache'
foreach ($path in @($input,$cache)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
Invoke-Native $docker @('image','save','--output',(Join-Path $input 'image.tar'),$localImage) *> (Join-Path $report 'save.log')
Invoke-Native $docker @('pull','aquasec/trivy:0.76.2') *> (Join-Path $report 'scan.log')
Write-Host '[SCAN] Blocking HIGH/CRITICAL vulnerabilities and secrets before registry publication or deployment.'
Invoke-Native $docker @('run','--rm','--mount',"type=bind,source=$input,target=/input,readonly",'--mount',"type=bind,source=$cache,target=/root/.cache",'--mount',"type=bind,source=$report,target=/reports",'aquasec/trivy:0.76.2','image','--input','/input/image.tar','--scanners','vuln,secret','--severity','HIGH,CRITICAL','--format','json','--output','/reports/trivy.json','--timeout','15m','--exit-code','0') *>> (Join-Path $report 'scan.log')
$scan = Get-Content -LiteralPath (Join-Path $report 'trivy.json') -Raw | ConvertFrom-Json
if ($scan.SchemaVersion -ne 2 -or -not $scan.PSObject.Properties['Results']) { throw 'The scanner did not produce a valid report.' }
$vulnerabilities = @($scan.Results | ForEach-Object { $_.Vulnerabilities } | Where-Object { $_ -and $_.Severity -in @('HIGH','CRITICAL') })
$secrets = @($scan.Results | ForEach-Object { $_.Secrets } | Where-Object { $_ -and $_.Severity -in @('HIGH','CRITICAL') })
$scanRow = [pscustomobject]@{ImageId=$imageId;High=@($vulnerabilities | Where-Object Severity -eq 'HIGH').Count;Critical=@($vulnerabilities | Where-Object Severity -eq 'CRITICAL').Count;Secrets=$secrets.Count}
$scanRow | Export-Csv -LiteralPath (Join-Path $report 'scan-summary.csv') -NoTypeInformation -Encoding UTF8
if ($vulnerabilities.Count -gt 0 -or $secrets.Count -gt 0) { $scanRow | Format-List | Out-Host; throw "Image blocked. Review $report\trivy.json. No runtime service was deployed." }
Write-Host '[PASS] Image scan: zero HIGH/CRITICAL vulnerabilities or secrets.'

$imageRecordPath = Join-Path $report 'image.json'
$imageRecord = if (Test-Path -LiteralPath $imageRecordPath) { Get-Content -LiteralPath $imageRecordPath -Raw | ConvertFrom-Json } else { $null }
if ($imageRecord -and $imageRecord.ImageId -eq $imageId -and $imageRecord.Reference -match ("^" + [regex]::Escape("$registry/$Repository") + "@sha256:[a-f0-9]{64}$")) {
    $digest = (Invoke-Native $azure @('acr','repository','show','--name',$registryName,'--subscription',$subscription,'--image',($Repository + ':' + $imageRecord.Tag),'--query','digest','-o','tsv','--only-show-errors') | Out-String).Trim()
    if ($imageRecord.Reference -ne "$registry/$Repository@$digest") { throw 'The stored registry digest does not match.' }
    $imageRef = $imageRecord.Reference
    Write-Host '[PASS] Reusing the same scanned immutable registry digest.'
} else {
    $tag = ($Repository + '-') + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $remoteImage = "$registry/${Repository}:$tag"
    Invoke-Native $azure @('acr','login','--name',$registryName,'--subscription',$subscription,'--only-show-errors') | Out-Host
    Invoke-Native $docker @('tag',$localImage,$remoteImage) | Out-Null
    Invoke-Native $docker @('push',$remoteImage) *> (Join-Path $report 'push.log')
    $digest = (Invoke-Native $azure @('acr','repository','show','--name',$registryName,'--subscription',$subscription,'--image',($Repository + ':' + $tag),'--query','digest','-o','tsv','--only-show-errors') | Out-String).Trim()
    if ($digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'An immutable registry digest was not returned.' }
    Invoke-Native $azure @('acr','repository','update','--name',$registryName,'--subscription',$subscription,'--image',($Repository + ':' + $tag),'--write-enabled','false','--delete-enabled','false','--only-show-errors') | Out-Null
    $imageRef = "$registry/$Repository@$digest"
    @{ImageId=$imageId;Tag=$tag;Reference=$imageRef} | ConvertTo-Json | Set-Content -LiteralPath $imageRecordPath -Encoding ASCII
}


    return $imageRef
}
