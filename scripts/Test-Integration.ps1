[CmdletBinding()]
param([ValidateRange(30,900)][int]$TimeoutSeconds = 360)
$ErrorActionPreference = 'Stop'
# Rebuild and scan before executing the security-sensitive registration changes.
& (Join-Path $PSScriptRoot 'Validate-SecurityUpgrade.ps1')
& (Join-Path $PSScriptRoot 'Test-Runtime.ps1') -IncludeIntegration -TimeoutSeconds $TimeoutSeconds
