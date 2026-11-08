[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Write-Host '[1/3] Validate configuration, compile, and run the Java tests.'
& (Join-Path $PSScriptRoot 'Validate-Local.ps1')
Write-Host '[2/3] Rebuild local images with the updated dependencies and base packages.'
& (Join-Path $PSScriptRoot 'Validate-Local.ps1') -ImagesOnly
Write-Host '[3/3] Rescan the rebuilt images. Findings still block release.'
& (Join-Path $PSScriptRoot 'Scan-Images.ps1')
Write-Host 'Security upgrade checks passed. Azure has not been changed.'
