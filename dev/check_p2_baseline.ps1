[CmdletBinding()]
param(
    [switch]$NoCache,
    [switch]$UsePreparedImages,
    [string]$UnitImage
)
if ($UsePreparedImages) {
    if ([string]::IsNullOrWhiteSpace($UnitImage) -or $UnitImage.StartsWith('-') -or $UnitImage -match '[\s\x00-\x1f$#]') { throw 'UsePreparedImages requires -UnitImage with a local image reference' }
    if ($NoCache) { throw 'NoCache cannot be used with UsePreparedImages' }
} elseif ($PSBoundParameters.ContainsKey('UnitImage')) { throw 'UnitImage requires UsePreparedImages' }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-architecture.ps1')
$repo = Split-Path $PSScriptRoot
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p2-baseline/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$console = Join-Path $results 'console.log'
$hostRecord = [ordered]@{ startedUtc=(Get-Date).ToUniversalTime().ToString('o'); result='running'; stage='engine'; imageTag=('https-portal-p2-unit:' + $runId) }
$hostRecord.mode = if ($UsePreparedImages) { 'prepared-images' } else { 'build-and-test' }
if ($UsePreparedImages) { $hostRecord.imageTag = $UnitImage }
function Invoke-Docker {
    param([string[]]$DockerArgs)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    & docker @DockerArgs 2>&1 | ForEach-Object {
        # Windows PowerShell wraps native stderr, including blank lines.
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
        else { $_.ToString() }
    } | Tee-Object -FilePath $console -Append
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "Docker operation failed (exit $code); see console.log" }
}
try {
    # GitHub-hosted Linux runners use a different UID from the container's 1000.
    # Grant access only to this run's output directory, never the source tree.
    if ($PSVersionTable.Platform -eq 'Unix') {
        & chmod '0777' '--' $results
        if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare the container output directory' }
    }
    if ($env:GITHUB_ACTIONS -eq 'true') {
        $hostRecord.github = [ordered]@{
            event=$env:GITHUB_EVENT_NAME; runId=$env:GITHUB_RUN_ID
            runAttempt=$env:GITHUB_RUN_ATTEMPT; expectedSha=$env:GITHUB_SHA
        }
    }
    # Host prerequisites are Docker CLI and PowerShell only; Git runs in Docker.
    Invoke-Docker -DockerArgs @('version')
    $engineOS = & docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0 -or $engineOS -ne 'linux') { throw 'A reachable Linux Docker Engine is required' }
    if (!$UsePreparedImages) {
        $hostRecord.stage = 'build'
        $buildArgs = @('build','--progress=plain','-f',(Join-Path $repo 'spec/ci/Dockerfile.unit'),'-t',$hostRecord.imageTag)
        if ($NoCache) { $buildArgs += '--no-cache' }
        Invoke-Docker -DockerArgs ($buildArgs + @($repo))
    }
    $hostRecord.stage = 'image-preflight'
    $imageJson = & docker image inspect --format '{"Id":{{json .Id}},"Os":{{json .Os}},"Architecture":{{json .Architecture}}}' $hostRecord.imageTag
    if ($LASTEXITCODE -ne 0) { throw 'Local unit image is unavailable; prepare or load it before testing. No image will be pulled.' }
    $imageInfo = ($imageJson | Out-String) | ConvertFrom-Json
    if ($imageInfo.Id -notmatch '^sha256:[0-9a-f]{64}$' -or $imageInfo.Os -ne 'linux') { throw 'Expected a local Linux image with a valid image ID' }
    Assert-CIImageArchitecture $imageInfo.Architecture 'unit image'
    $hostRecord.imageId = $imageInfo.Id
    $hostRecord.imagePlatform = $imageInfo.Os + '/' + $imageInfo.Architecture
    $hostRecord.stage = 'offline-test'
    Invoke-Docker -DockerArgs @('run','--pull','never','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--tmpfs','/tmp:rw,nosuid,nodev,size=256m','--mount',('type=bind,source=' + $repo + ',target=/checkout,readonly'),'--mount',('type=bind,source=' + $results + ',target=/results'),$hostRecord.imageId)
    $baseline = Get-Content -Raw -LiteralPath (Join-Path $results 'baseline.json') | ConvertFrom-Json
    if ($baseline.result -ne 'passed') { throw 'Container baseline did not pass' }
    $hostRecord.result = 'passed'
    $hostRecord.stage = 'complete'
}
catch { $hostRecord.result = 'failed'; $hostRecord.failure = $_.Exception.Message; throw }
finally {
    $hostRecord.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    [IO.File]::WriteAllText((Join-Path $results 'host-run.json'), ($hostRecord | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Write-Output ('Evidence: dev/test-results/p2-baseline/' + $runId)
}
