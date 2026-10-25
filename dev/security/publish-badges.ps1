[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'badges.ps1')
if($env:GITHUB_EVENT_NAME -notin @('push','schedule','workflow_dispatch') -or !$env:SECURITY_BADGE_DATA){throw 'A trusted branch collection is required'}
try {$data=$env:SECURITY_BADGE_DATA | ConvertFrom-Json}catch{throw 'Invalid security count badge payload'}
$null=Publish-SecurityBadgeData $data $env:GITHUB_REPOSITORY $env:GITHUB_REF_NAME $env:GITHUB_SHA
