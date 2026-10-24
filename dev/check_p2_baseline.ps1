[CmdletBinding()]
param([switch]$NoCache)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p2-baseline/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$console = Join-Path $results 'console.log'
$hostRecord = [ordered]@{ startedUtc=(Get-Date).ToUniversalTime().ToString('o'); result='running'; stage='engine'; imageTag=('https-portal-p2-unit:' + $runId) }
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
    $hostRecord.stage = 'build'
    $buildArgs = @('build','--progress=plain','-f',(Join-Path $repo 'spec/ci/Dockerfile.unit'),'-t',$hostRecord.imageTag)
    if ($NoCache) { $buildArgs += '--no-cache' }
    Invoke-Docker -DockerArgs ($buildArgs + @($repo))
    $hostRecord.imageId = (& docker image inspect --format '{{.Id}}' $hostRecord.imageTag)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record built image ID' }
    $hostRecord.stage = 'offline-test'
    Invoke-Docker -DockerArgs @('run','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--tmpfs','/tmp:rw,nosuid,nodev,size=256m','--mount',('type=bind,source=' + $repo + ',target=/checkout,readonly'),'--mount',('type=bind,source=' + $results + ',target=/results'),$hostRecord.imageTag)
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
