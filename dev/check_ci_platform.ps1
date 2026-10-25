[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('amd64','arm64')][string]$ExpectedArchitecture)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci-architecture.ps1')
$json=& docker info --format '{"os":{{json .OSType}},"architecture":{{json .Architecture}}}'
if($LASTEXITCODE -ne 0){throw 'Cannot inspect Docker architecture'}
$engine=($json | Out-String)|ConvertFrom-Json
$hostArchitecture=([Runtime.InteropServices.RuntimeInformation]::OSArchitecture).ToString()
$processArchitecture=([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture).ToString()
Assert-CINativePlatform $ExpectedArchitecture $hostArchitecture $processArchitecture $engine.os $engine.architecture $env:RUNNER_ARCH $env:DOCKER_DEFAULT_PLATFORM
Write-Host ('Native CI platform verified: linux/'+$ExpectedArchitecture+'; host='+$hostArchitecture+'; process='+$processArchitecture+'; Docker='+$engine.architecture)
