[CmdletBinding()]
param(
    [ValidateSet('api-gateway','auth-service','cart-service','category-service','notification-service','order-service','product-service','service-registry','user-service','frontend')]
    [string[]]$Services = @('product-service','auth-service','api-gateway','cart-service','category-service','notification-service','order-service','service-registry','user-service','frontend')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$scanDirectory = Join-Path $projectRoot '.validation\trivy'
$inputDirectory = Join-Path $scanDirectory 'input'
$cacheDirectory = Join-Path $scanDirectory 'cache'
$reportDirectory = Join-Path $scanDirectory 'reports'
foreach ($directory in @($inputDirectory,$cacheDirectory,$reportDirectory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$dockerCommand = Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1
$dockerPath = $dockerCommand.Path
$scannerImage = 'aquasec/trivy:0.76.2'
function Invoke-Docker {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    & $dockerPath @Arguments
    $nativeExitCode = $LASTEXITCODE
    if ($nativeExitCode -ne 0) { throw "Docker exited with code $nativeExitCode" }
}
function Get-FindingCounts {
    param([object]$Report)
    $vulnerabilities = @($Report.Results | ForEach-Object { $_.Vulnerabilities } | Where-Object { $_ })
    $secrets = @($Report.Results | ForEach-Object { $_.Secrets } | Where-Object { $_ -and $_.Severity -in @('HIGH','CRITICAL') })
    [pscustomobject]@{
        High = @($vulnerabilities | Where-Object Severity -eq 'HIGH').Count
        Critical = @($vulnerabilities | Where-Object Severity -eq 'CRITICAL').Count
        Secrets = $secrets.Count
    }
}
$preflightLog = Join-Path $scanDirectory 'preflight.log'
Invoke-Docker @('info','--format','{{.ServerVersion}}') *> $preflightLog
Write-Host '[PREPARE] Downloading the pinned Trivy scanner image, if needed.'
Invoke-Docker @('pull',$scannerImage) *> $preflightLog
$results = [System.Collections.Generic.List[object]]::new()
$archivePath = Join-Path $inputDirectory 'image.tar'
foreach ($service in $Services) {
    $image = "purely-local/${service}:validation"
    $jsonPath = Join-Path $reportDirectory ($service + '.json')
    $logPath = Join-Path $scanDirectory ($service + '.log')
    try {
        Write-Host "[SCAN] $service"
        $imageId = (Invoke-Docker @('image','inspect','--format','{{.Id}}',$image) | Out-String).Trim()
        # Reuse one archive; do not expose Docker sockets or credentials to Trivy.
        Invoke-Docker @('image','save','--output',$archivePath,$image) *> $logPath
        $scanArguments = @(
            'run','--rm',
            '--mount',"type=bind,source=$inputDirectory,target=/input,readonly",
            '--mount',"type=bind,source=$cacheDirectory,target=/root/.cache",
            '--mount',"type=bind,source=$reportDirectory,target=/reports",
            $scannerImage,'image','--input','/input/image.tar',
            '--scanners','vuln,secret','--severity','HIGH,CRITICAL',
            '--format','json','--output',"/reports/$service.json",
            '--timeout','15m','--exit-code','0'
        )
        Invoke-Docker $scanArguments *>> $logPath
        $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        if ($report.SchemaVersion -ne 2 -or -not $report.ArtifactName -or -not $report.PSObject.Properties['Results']) {
            throw 'Scanner output is missing required report fields.'
        }
        $counts = Get-FindingCounts $report
        $status = if (($counts.High + $counts.Critical + $counts.Secrets) -eq 0) { 'PASS' } else { 'BLOCKED' }
        $results.Add([pscustomobject]@{
            Service=$service; Status=$status; High=$counts.High; Critical=$counts.Critical;
            Secrets=$counts.Secrets; ImageId=$imageId; Scanner=$scannerImage; Report=$jsonPath
        })
        Write-Host "[$status] $service HIGH=$($counts.High) CRITICAL=$($counts.Critical) SECRETS=$($counts.Secrets)"
    } catch {
        $_ | Out-File -LiteralPath $logPath -Append
        $results.Add([pscustomobject]@{
            Service=$service; Status='ERROR'; High=$null; Critical=$null;
            Secrets=$null; ImageId=$null; Scanner=$scannerImage; Report=$logPath
        })
        Write-Host "[ERROR] $service - see $logPath"
    }
}
$csvPath = Join-Path $scanDirectory 'scan-summary.csv'
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$results | Format-Table Service,Status,High,Critical,Secrets -AutoSize
Write-Host "Report: $csvPath"
if (@($results | Where-Object Status -ne 'PASS').Count -gt 0) {
    throw 'Security gate not passed. Review findings or scanner errors before release.'
}
