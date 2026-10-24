[CmdletBinding()]
param(
    [ValidateSet('local','never-ready')][string]$Scenario = 'local',
    [ValidateRange(1,10)][int]$Repeat = 1,
    [ValidateRange(1,900)][int]$StartupTimeoutSeconds = 180,
    [switch]$NoCache,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ').ToLowerInvariant() + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p2-integration/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$docker = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$composeFile = Join-Path $repo 'spec/ci/compose.yaml'
$envFile = Join-Path $results 'fixture.env'
$environment = @{
    IT_PORTAL_IMAGE=('https-portal-it:' + $runId)
    IT_TEST_IMAGE=('https-portal-it-tools:' + $runId)
    IT_STARTUP_TIMEOUT_SECONDS=$StartupTimeoutSeconds.ToString()
}
# Explicit, generated fixture values; never load the user's project .env.
[IO.File]::WriteAllText($envFile, (($environment.Keys | Sort-Object | ForEach-Object { $_ + '=' + $environment[$_] }) -join "`n") + "`n", $utf8)
$record = [ordered]@{ startedUtc=(Get-Date).ToUniversalTime().ToString('o'); scenario=$Scenario; repeat=$Repeat; result='running'; stage='configuration'; runs=@() }
$failure = $null

function Quote-NativeArgument([string]$Value) {
    # Windows C runtime quoting, for Windows PowerShell 5.1 ProcessStartInfo.
    '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}
function Invoke-DockerBounded {
    param([string[]]$DockerArgs, [int]$TimeoutSeconds=60, [string]$LogName, [switch]$AllowFailure)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $docker
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($info.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in $DockerArgs) { $info.ArgumentList.Add($argument) }
    } else { $info.Arguments = ($DockerArgs | ForEach-Object { Quote-NativeArgument $_ }) -join ' ' }
    foreach ($key in $environment.Keys) { $info.EnvironmentVariables[$key] = $environment[$key] }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $timedOut = $false
    try {
        if (!$process.Start()) { throw 'Could not start Docker CLI' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        Write-Host ("Running $LogName (limit ${TimeoutSeconds}s)")
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $nextProgress = 30
        while (!$process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                try { $process.Kill() } catch { }
                $null = $process.WaitForExit(5000)
                break
            }
            if ($watch.Elapsed.TotalSeconds -ge $nextProgress) {
                Write-Host ("Still running $LogName ({0:N0}s elapsed)" -f $watch.Elapsed.TotalSeconds)
                $nextProgress += 30
            }
        }
        $watch.Stop()
        # A killed CLI or its child may retain the pipe; never wait indefinitely.
        $null = $stdoutTask.Wait(5000)
        $null = $stderrTask.Wait(5000)
        $stdout = if ($stdoutTask.IsCompleted) { $stdoutTask.GetAwaiter().GetResult() } else { '[stdout capture did not complete]' }
        $stderr = if ($stderrTask.IsCompleted) { $stderrTask.GetAwaiter().GetResult() } else { '[stderr capture did not complete]' }
        $code = if ($timedOut) { 124 } elseif ($process.HasExited) { $process.ExitCode } else { 125 }
        if ($LogName) {
            [IO.File]::WriteAllText((Join-Path $results ($LogName + '.stdout.log')), $stdout, $utf8)
            [IO.File]::WriteAllText((Join-Path $results ($LogName + '.stderr.log')), $stderr, $utf8)
        }
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($stderr) { Write-Host $stderr.TrimEnd() }
        if ($code -ne 0 -and !$AllowFailure) { throw "Docker operation failed: $LogName (exit $code, timeout=$timedOut)" }
        [pscustomobject]@{ code=$code; stdout=$stdout; stderr=$stderr; timedOut=$timedOut }
    } finally { $process.Dispose() }
}
function Compose-Args([string]$Project) {
    @('compose','--profile','test','--project-directory',$repo,'--env-file',$envFile,'-p',$Project,'-f',$composeFile)
}
function Assert-IsolatedConfig($Config) {
    if ($Config.networks.isolated.internal -ne $true) { throw 'Fixture must use an internal network' }
    if ($Config.networks.isolated.name -ne ($Config.name + '_isolated')) { throw 'Network must be scoped to this project' }
    foreach ($entry in $Config.volumes.PSObject.Properties) {
        if ($entry.Value.external -or $entry.Value.name -ne ($Config.name + '_' + $entry.Name)) { throw 'Volumes must be scoped to this project' }
    }
    foreach ($entry in $Config.services.PSObject.Properties) {
        $service = $entry.Value
        if ($service.ports -or $service.privileged -or $service.network_mode -or $service.container_name) { throw 'Unsafe fixture runtime configuration' }
        if ($service.pull_policy -ne 'never') { throw 'Fixture must not pull at runtime' }
        if ($service.networks.PSObject.Properties.Name.Count -ne 1 -or !($service.networks.PSObject.Properties.Name -contains 'isolated')) { throw 'Service is connected outside the isolated network' }
        foreach ($volume in $service.volumes) { if ($volume.type -ne 'volume') { throw 'Fixture may use only project-local named volumes' } }
        if ($service.environment.DEBUG) { throw 'DEBUG must not be set' }
    }
    if ($Config.services.portal.environment.STAGE -ne 'local' -or $Config.services.portal.environment.DOMAINS -ne 'portal.test') { throw 'Only the fixed local-stage domain is allowed' }
}
function Find-Resources([string]$Project,[string]$Prefix) {
    $found = [ordered]@{}
    foreach ($kind in @('container','network','volume')) {
        $args = switch ($kind) {
            'container' { @('ps','-aq','--filter',('label=com.docker.compose.project=' + $Project)) }
            'network' { @('network','ls','-q','--filter',('label=com.docker.compose.project=' + $Project)) }
            'volume' { @('volume','ls','-q','--filter',('label=com.docker.compose.project=' + $Project)) }
        }
        $out = Invoke-DockerBounded -DockerArgs $args -TimeoutSeconds 20 -LogName ($Prefix + '-' + $kind)
        $found[$kind] = @($out.stdout -split '\r?\n' | Where-Object { $_.Trim() })
    }
    $found
}
try {
    Invoke-DockerBounded -DockerArgs @('compose','version') -TimeoutSeconds 30 -LogName 'compose-version' | Out-Null
    $configuration = Invoke-DockerBounded -DockerArgs ((Compose-Args ('hp-it-' + $runId + '-config')) + @('config','--format','json')) -TimeoutSeconds 30 -LogName 'compose-config'
    Assert-IsolatedConfig ($configuration.stdout | ConvertFrom-Json)
    if ($ValidateOnly) {
        $record.result = 'validated'
        $record.stage = 'complete'
        Write-Host 'P2-03 configuration validated; no Docker runtime was started.'
    } else {
        $record.stage = 'engine'
        Invoke-DockerBounded -DockerArgs @('version') -LogName 'docker-version' | Out-Null
        $os = Invoke-DockerBounded -DockerArgs @('info','--format','{{.OSType}}') -LogName 'engine-os'
        if ($os.stdout.Trim() -ne 'linux') { throw 'A Linux Docker Engine is required' }
        $record.stage = 'build'
        $extra = if ($NoCache) { @('--no-cache') } else { @() }
        Invoke-DockerBounded -DockerArgs (@('build','--progress=plain','-t',$environment.IT_PORTAL_IMAGE) + $extra + @($repo)) -TimeoutSeconds 1200 -LogName 'build-portal' | Out-Null
        Invoke-DockerBounded -DockerArgs (@('build','--progress=plain','-f',(Join-Path $repo 'spec/ci/Dockerfile.integration'),'-t',$environment.IT_TEST_IMAGE) + $extra + @($repo)) -TimeoutSeconds 600 -LogName 'build-tools' | Out-Null
        foreach ($image in @('IT_PORTAL_IMAGE','IT_TEST_IMAGE')) {
            $imageInfo = Invoke-DockerBounded -DockerArgs @('image','inspect','--format','{{.Id}}',$environment[$image]) -LogName ('image-' + $image)
            $record[$image] = $imageInfo.stdout.Trim()
        }
        $record.stage = 'scenarios'
        foreach ($iteration in 1..$Repeat) {
            $project = 'hp-it-' + $runId + '-' + $iteration
            $prefix = 'run-' + $iteration
            $args = Compose-Args $project
            $current = [ordered]@{ project=$project; iteration=$iteration; result='running'; cleanup='pending'; diagnosticsErrors=@() }
            # Check before entering the cleanup scope: never delete a pre-existing project.
            $initial = Find-Resources $project ($prefix + '-before')
            if ($initial.container.Count -or $initial.network.Count -or $initial.volume.Count) { throw 'Project resources already exist; refusing to reuse them' }
            $record.runs += $current
            [IO.File]::WriteAllText((Join-Path $results 'result.json'), ($record | ConvertTo-Json -Depth 12), $utf8)
            try {
                Invoke-DockerBounded -DockerArgs ($args + @('up','-d','--no-build','--pull','never','portal','echo')) -TimeoutSeconds 90 -LogName ($prefix + '-up') | Out-Null
                $net = Invoke-DockerBounded -DockerArgs @('network','inspect','--format','{{.Internal}}',($project + '_isolated')) -TimeoutSeconds 20 -LogName ($prefix + '-network-internal')
                if ($net.stdout.Trim() -ne 'true') { throw 'Created network is not internal' }
                $testArgs = @('run','--rm','--no-deps','-T')
                if ($Scenario -eq 'never-ready') { $testArgs += @('-e','IT_EXPECTED_BODY=__intentional_readiness_failure__') }
                $testArgs += 'tester'
                Invoke-DockerBounded -DockerArgs ($args + $testArgs) -TimeoutSeconds ($StartupTimeoutSeconds + 30) -LogName ($prefix + '-probe') | Out-Null
                $current.result = 'passed'
            } catch { $current.result='failed'; $current.failure=$_.Exception.Message; $failure=$_.Exception.Message }
            finally {
                $diagnostics = [ordered]@{
                    ps=@('ps','-a','--format','json')
                    logs=@('logs','--no-color','--timestamps','--tail','300','portal','echo')
                    http=@('exec','-T','portal','cat','/etc/nginx/conf.d/portal.test.conf')
                    https=@('exec','-T','portal','cat','/etc/nginx/conf.d/portal.test.ssl.conf')
                    certificate=@('exec','-T','portal','openssl','x509','-in','/var/lib/https-portal/portal.test/local/signed.crt','-noout','-subject','-issuer','-dates','-fingerprint','-sha256')
                }
                foreach ($key in $diagnostics.Keys) {
                    try {
                        $diag = Invoke-DockerBounded -DockerArgs ($args + $diagnostics[$key]) -TimeoutSeconds 20 -LogName ($prefix + '-diagnostic-' + $key) -AllowFailure
                        if ($diag.code -ne 0) { $current.diagnosticsErrors += ($key + ': exit ' + $diag.code) }
                    } catch { $current.diagnosticsErrors += ($key + ': collection failed') }
                }
                $current.diagnostics = if ($current.diagnosticsErrors.Count) { 'partial' } else { 'passed' }
                if ($current.diagnosticsErrors.Count -and !$failure) { $failure='Required diagnostics collection was incomplete' }
                try {
                    # Only the freshly allocated project; never prune shared resources.
                    Invoke-DockerBounded -DockerArgs ($args + @('down','--volumes','--remove-orphans','--timeout','10')) -TimeoutSeconds 60 -LogName ($prefix + '-cleanup') | Out-Null
                    $remaining = Find-Resources $project ($prefix + '-after')
                    $current.remaining = $remaining
                    if ($remaining.container.Count -or $remaining.network.Count -or $remaining.volume.Count) { throw 'Project resources remain after cleanup' }
                    $current.cleanup = 'passed'
                } catch { $current.cleanup='failed'; $current.cleanupFailure=$_.Exception.Message; if (!$failure) { $failure=$_.Exception.Message } }
            }
            if ($failure) { break }
        }
        if ($failure) { throw $failure }
        $record.result = 'passed'
        $record.stage = 'complete'
        Write-Host ("P2-03 integration foundation passed ($Repeat isolated run(s), cleanup verified).")
    }
} catch { $record.result='failed'; $record.failure=$_.Exception.Message; $failure=$_.Exception.Message }
finally {
    $record.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    [IO.File]::WriteAllText((Join-Path $results 'result.json'), ($record | ConvertTo-Json -Depth 12), $utf8)
    Write-Host ('Evidence: dev/test-results/p2-integration/' + $runId)
}
if ($failure) { throw $failure }
