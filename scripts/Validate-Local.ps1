[CmdletBinding()]
param([switch]$SkipBuilds, [switch]$IncludeImages, [switch]$ImagesOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$reportDirectory = Join-Path $projectRoot '.validation'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$results = [System.Collections.Generic.List[object]]::new()
function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    $executable = Get-Command $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1
    # Windows PowerShell 5.1 turns redirected stderr into NativeCommandError.
    # Build progress on stderr is normal; the native exit code decides success.
    $ErrorActionPreference = 'Continue'
    & $executable.Path @Arguments
    $nativeExitCode = $LASTEXITCODE
    if ($nativeExitCode -ne 0) {
        throw "$Command exited with code $nativeExitCode"
    }
}
function Invoke-Check {
    param([string]$Name, [string]$Directory, [scriptblock]$Action)
    $log = Join-Path $reportDirectory ($Name + '.log')
    Push-Location -LiteralPath $Directory
    try {
        $global:LASTEXITCODE = 0
        & $Action *> $log
        if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
        $results.Add([pscustomobject]@{Check=$Name; Status='PASS'; Log=$log})
        Write-Host "[PASS] $Name"
    } catch {
        $_ | Out-File -LiteralPath $log -Append
        $results.Add([pscustomobject]@{Check=$Name; Status='FAIL'; Log=$log})
        Write-Host "[FAIL] $Name - see $log"
    } finally { Pop-Location }
}
if (-not (Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path 'C:\Program Files\nodejs')) {
    $env:PATH = 'C:\Program Files\nodejs;' + $env:PATH
}
if (-not $env:JAVA_HOME -and (Test-Path 'C:\Program Files\Java\jdk-21')) {
    $env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
}
$terraformCommand = Get-Command terraform -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$terraform = if ($terraformCommand) { $terraformCommand.Path } elseif (Test-Path 'C:\Terraform\terraform.exe') { 'C:\Terraform\terraform.exe' } else { 'terraform' }
$mavenCommand = Get-Command mvn.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$maven = if ($mavenCommand) { $mavenCommand.Path } else {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.m2\wrapper\dists') -Recurse -File -Filter mvn.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $candidate.FullName } else { 'mvn.cmd' }
}
if (-not $ImagesOnly) {
Invoke-Check 'configuration' $projectRoot { Invoke-Native 'node' @('scripts/check-config.cjs') }
foreach ($chart in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'k8s\charts') -Directory) {
    $chartPath = $chart.FullName
    Invoke-Check ('helm-' + $chart.Name) $projectRoot {
        Invoke-Native 'helm' @('lint', $chartPath, '--strict')
        Invoke-Native 'helm' @('template', 'verify', $chartPath) | Out-Null
    }
}
Invoke-Check 'helm-observability' $projectRoot { Invoke-Native 'helm' @('lint', 'k8s/observability', '--strict') }
Invoke-Check 'terraform-fmt' $projectRoot { Invoke-Native $terraform @('-chdir=infra', 'fmt', '-check', '-recursive') }
Invoke-Check 'terraform-init' $projectRoot { Invoke-Native $terraform @('-chdir=infra', 'init', '-backend=false', '-input=false') }
Invoke-Check 'terraform-validate' $projectRoot { Invoke-Native $terraform @('-chdir=infra', 'validate', '-no-color') }
if (-not $SkipBuilds) {
    foreach ($service in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'microservice-backend') -Directory) {
        Invoke-Check ('java-' + $service.Name) $service.FullName {
            Invoke-Native $maven @('-B', 'verify', '-Dspring.profiles.active=test')
        }
    }
    Invoke-Check 'frontend-build' (Join-Path $projectRoot 'frontend') {
        Invoke-Native 'npm.cmd' @('ci', '--no-audit', '--no-fund')
        Invoke-Native 'npm.cmd' @('run', 'build')
    }
}
}
if ($IncludeImages -or $ImagesOnly) {
    Invoke-Check 'docker-engine' $projectRoot {
        Invoke-Native 'docker' @('info', '--format', '{{.ServerVersion}}')
    }
    if ($results[$results.Count - 1].Status -eq 'PASS') {
    foreach ($service in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'microservice-backend') -Directory) {
        $imageName = $service.Name
        $contextPath = $service.FullName
        Invoke-Check ('image-' + $imageName) $projectRoot {
            Invoke-Native 'docker' @('build', '--pull', '-t', "purely-local/${imageName}:validation", $contextPath)
        }
    }
    Invoke-Check 'image-frontend' $projectRoot { Invoke-Native 'docker' @('build', '--pull', '-t', 'purely-local/frontend:validation', 'frontend') }
    }
}
$reportName = if ($ImagesOnly) { 'image-validation-results.csv' } else { 'validation-results.csv' }
$csv = Join-Path $reportDirectory $reportName
$results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$results | Format-Table Check,Status -AutoSize
Write-Host "Report: $csv"
if ($results.Status -contains 'FAIL') { throw 'Resolve failed checks before deployment.' }
