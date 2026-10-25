[CmdletBinding()]
param(
    [ValidateSet('local','never-ready','redirect','proxy','auth','ca','persistence','renewal','static','ip','ip-auth','tls-policy','tls-chain','tls-expired','tls','security','all')][string]$Scenario = 'local',
    [ValidateRange(1,10)][int]$Repeat = 1,
    [ValidateRange(1,900)][int]$StartupTimeoutSeconds = 180,
    [switch]$NoCache,
    [switch]$ValidateOnly,
    [switch]$UsePreparedImages,
    [string]$PortalImage,
    [string]$TestImage,
    [ValidateSet('none','disable-tls12')][string]$TLSMutation = 'none'
)
if ($TLSMutation -ne 'none' -and $Scenario -ne 'tls-policy') { throw 'TLSMutation requires Scenario tls-policy' }
if ($UsePreparedImages) {
    foreach ($reference in @($PortalImage, $TestImage)) {
        if ([string]::IsNullOrWhiteSpace($reference) -or $reference.StartsWith('-') -or $reference -match '[\s\x00-\x1f$#]') { throw 'UsePreparedImages requires both -PortalImage and -TestImage with local image references' }
    }
    if ($NoCache) { throw 'NoCache cannot be used with UsePreparedImages' }
} elseif ($PSBoundParameters.ContainsKey('PortalImage') -or $PSBoundParameters.ContainsKey('TestImage')) { throw 'Image references require UsePreparedImages' }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-architecture.ps1')
$repo = Split-Path $PSScriptRoot
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ').ToLowerInvariant() + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p2-integration/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$docker = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$composeFile = Join-Path $repo 'spec/ci/compose.yaml'
$envFile = $null
$environment = @{
    IT_PORTAL_IMAGE=('https-portal-it:' + $runId)
    IT_TEST_IMAGE=('https-portal-it-tools:' + $runId)
    IT_STARTUP_TIMEOUT_SECONDS=$StartupTimeoutSeconds.ToString()
    IT_SCENARIO='local'
    IT_DOMAINS='portal.test'
    IT_ALLOWED_IP='192.0.2.10'
}

$record = [ordered]@{ startedUtc=(Get-Date).ToUniversalTime().ToString('o'); scenario=$Scenario; repeat=$Repeat; result='running'; stage='configuration'; runs=@() }
if ($env:GITHUB_ACTIONS -eq 'true') {
    $record.github = [ordered]@{
        event=$env:GITHUB_EVENT_NAME; runId=$env:GITHUB_RUN_ID
        runAttempt=$env:GITHUB_RUN_ATTEMPT; expectedSha=$env:GITHUB_SHA
    }
}
$record.tlsMutation = $TLSMutation
$record.mode = if ($UsePreparedImages) { 'prepared-images' } else { 'build-and-test' }
if ($UsePreparedImages) {
    $environment.IT_PORTAL_IMAGE = $PortalImage
    $environment.IT_TEST_IMAGE = $TestImage
}
$record.requestedImages = [ordered]@{ portal=$environment.IT_PORTAL_IMAGE; tools=$environment.IT_TEST_IMAGE }
$failure = $null
$scenarios = if ($Scenario -eq 'all') { @('local','redirect','proxy','auth','ca','persistence','renewal','static','ip','ip-auth','tls-policy','tls-chain','tls-expired') } elseif ($Scenario -eq 'tls') { @('tls-policy','tls-chain','tls-expired') } elseif ($Scenario -eq 'security') { @('ip','ip-auth','tls-policy','tls-chain','tls-expired') } else { @($Scenario) }

function Protect-LogText([string]$Text) {
    foreach ($secret in @('fixture-user:fixture-password','fixture-user:wrong-password')) {
        $Text = $Text.Replace([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret)), '[REDACTED]')
    }
    foreach ($value in @('fixture-user','fixture-password','wrong-password')) { $Text = $Text.Replace($value, '[REDACTED]') }
    $Text
}
function Set-ScenarioEnvironment([string]$Name) {
    $environment.IT_SCENARIO = $Name
    $environment.IT_DOMAINS = switch ($Name) {
        'proxy' { 'proxy.test -> http://echo:8080' }
        'auth' { 'fixture-user:fixture-password@auth.test -> http://echo:8080' }
        'ip' { '[' + $environment.IT_ALLOWED_IP + ']ip.test -> http://echo:8080' }
        'ip-auth' { '[' + $environment.IT_ALLOWED_IP + ']fixture-user:fixture-password@ip-auth.test -> http://echo:8080' }
        'tls-policy' { 'tls.test' }
        'tls-chain' { 'tls.test' }
        'tls-expired' { 'tls.test' }
        'ca' { 'tls.test' }
        'static' { 'static.test' }
        default { 'portal.test' }
    }
    $script:activeHost = switch ($Name) { 'proxy' { 'proxy.test' } 'auth' { 'auth.test' } 'ip' { 'ip.test' } 'ip-auth' { 'ip-auth.test' } 'tls-policy' { 'tls.test' } 'tls-chain' { 'tls.test' } 'tls-expired' { 'tls.test' } 'ca' { 'tls.test' } 'static' { 'static.test' } default { 'portal.test' } }
    $script:envFile = Join-Path $results ('fixture-' + $Name + '.env')
    [IO.File]::WriteAllText($envFile, (($environment.Keys | Sort-Object | ForEach-Object { $_ + '=' + $environment[$_] }) -join "`n") + "`n", $utf8)
}
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
            [IO.File]::WriteAllText((Join-Path $results ($LogName + '.stdout.log')), (Protect-LogText $stdout), $utf8)
            [IO.File]::WriteAllText((Join-Path $results ($LogName + '.stderr.log')), (Protect-LogText $stderr), $utf8)
        }
        if ($stdout) { Write-Host (Protect-LogText $stdout.TrimEnd()) }
        if ($stderr) { Write-Host (Protect-LogText $stderr.TrimEnd()) }
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
    $domains = @('portal.test','proxy.test -> http://echo:8080','fixture-user:fixture-password@auth.test -> http://echo:8080','tls.test','static.test',('[' + $environment.IT_ALLOWED_IP + ']ip.test -> http://echo:8080'),('[' + $environment.IT_ALLOWED_IP + ']fixture-user:fixture-password@ip-auth.test -> http://echo:8080'))
    if ($Config.services.portal.environment.STAGE -ne 'local' -or $Config.services.portal.environment.DOMAINS -notin $domains) { throw 'Only fixed internal local-stage domains are allowed' }
    foreach ($tester in @('tester','tester-allowed')) {
        foreach ($volume in $Config.services.$tester.volumes) { if ($volume.source -ne 'public') { throw 'Tester must not receive private certificate or site volumes' } }
    }
}
function Invoke-TLSContract([string[]]$ComposeArgs,[string]$Prefix,[string]$Phase,[string]$ScenarioName) {
    $probe = Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('run','--pull','never','--rm','--no-deps','-T','-e',('IT_PHASE=' + $Phase),'tester','ruby','/opt/it/tls_contracts.rb')) -TimeoutSeconds ($StartupTimeoutSeconds + 60) -LogName ($Prefix + '-tls-' + $Phase)
    $summary = ($probe.stdout -split '\r?\n' | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
    if ($summary.result -ne 'passed' -or $summary.scenario -ne $ScenarioName -or $summary.phase -ne $Phase -or !$summary.cases.Count) { throw 'Invalid TLS contract evidence' }
    $summary
}
function Hold-CertificateRenewal([string[]]$ComposeArgs,[string]$Prefix) {
    # Keep the product's existing advisory lock while abnormal certs are served.
    # The detached holder dies with this disposable portal container.
    $hold = 'lock=File.open("/tmp/https-portal.lock",File::CREAT); lock.flock(File::LOCK_EX); File.write("/tmp/it-cert-lock.ready","locked"); sleep ' + (3 * $StartupTimeoutSeconds + 120)
    Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('exec','-d','-T','portal','ruby','-e',$hold)) -TimeoutSeconds 20 -LogName ($Prefix + '-renew-lock-start') | Out-Null
    $wait = 'deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+10; until File.exist?("/tmp/it-cert-lock.ready"); raise "Renewal lock timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline; sleep 0.1; end; puts "renewal locked"'
    Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('exec','-T','portal','ruby','-e',$wait)) -TimeoutSeconds 15 -LogName ($Prefix + '-renew-lock-ready') | Out-Null
}
function Set-TLSFixture([string[]]$ComposeArgs,[string]$Prefix,[string]$Variant) {
    Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('run','--pull','never','--rm','--no-deps','-T','-e',('IT_TLS_VARIANT=' + $Variant),'prepare','ruby','/opt/it/switch_tls_fixture.rb')) -TimeoutSeconds 30 -LogName ($Prefix + '-switch-' + $Variant) | Out-Null
    Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('exec','-T','portal','nginx','-t')) -TimeoutSeconds 20 -LogName ($Prefix + '-nginx-test-' + $Variant) | Out-Null
    Invoke-DockerBounded -DockerArgs ($ComposeArgs + @('exec','-T','portal','nginx','-s','reload')) -TimeoutSeconds 20 -LogName ($Prefix + '-reload-' + $Variant) | Out-Null
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
    foreach ($planned in $scenarios) {
        Set-ScenarioEnvironment $planned
        $configuration = Invoke-DockerBounded -DockerArgs ((Compose-Args ('hp-it-' + $runId + '-config-' + $planned)) + @('config','--format','json')) -TimeoutSeconds 30 -LogName ('compose-config-' + $planned)
        Assert-IsolatedConfig ($configuration.stdout | ConvertFrom-Json)
    }
    if ($ValidateOnly) {
        $record.result = 'validated'
        $record.stage = 'complete'
        Write-Host 'Integration configuration validated; no Docker runtime was started.'
    } else {
        $record.stage = 'engine'
        Invoke-DockerBounded -DockerArgs @('version') -LogName 'docker-version' | Out-Null
        $os = Invoke-DockerBounded -DockerArgs @('info','--format','{{.OSType}}') -LogName 'engine-os'
        if ($os.stdout.Trim() -ne 'linux') { throw 'A Linux Docker Engine is required' }
        if (!$UsePreparedImages) {
            $record.stage = 'build'
            $extra = if ($NoCache) { @('--no-cache') } else { @() }
            Invoke-DockerBounded -DockerArgs (@('build','--progress=plain','-t',$environment.IT_PORTAL_IMAGE) + $extra + @($repo)) -TimeoutSeconds 1200 -LogName 'build-portal' | Out-Null
            Invoke-DockerBounded -DockerArgs (@('build','--progress=plain','-f',(Join-Path $repo 'spec/ci/Dockerfile.integration'),'-t',$environment.IT_TEST_IMAGE) + $extra + @($repo)) -TimeoutSeconds 600 -LogName 'build-tools' | Out-Null
        }
        $record.stage = 'image-preflight'
        $record.imagePlatforms = [ordered]@{}
        foreach ($image in @('IT_PORTAL_IMAGE','IT_TEST_IMAGE')) {
            $imageInfo = Invoke-DockerBounded -DockerArgs @('image','inspect','--format','{"Id":{{json .Id}},"Os":{{json .Os}},"Architecture":{{json .Architecture}}}',$environment[$image]) -LogName ('image-' + $image)
            $details = $imageInfo.stdout | ConvertFrom-Json
            if ($details.Id -notmatch '^sha256:[0-9a-f]{64}$' -or $details.Os -ne 'linux') { throw 'Expected a local Linux image with a valid image ID' }
            Assert-CIImageArchitecture $details.Architecture $image
            $record[$image] = $details.Id
            $record.imagePlatforms[$image] = $details.Os + '/' + $details.Architecture
            # Pin all subsequent Compose calls, even if a supplied tag is moved.
            $environment[$image] = $details.Id
        }
        $record.stage = 'scenarios'
        $sequence = 0
        foreach ($iteration in 1..$Repeat) {
          foreach ($activeScenario in $scenarios) {
            $sequence++
            Set-ScenarioEnvironment $activeScenario
            $project = 'hp-it-' + $runId + '-' + $sequence
            $prefix = 'run-' + $sequence
            $args = Compose-Args $project
            $current = [ordered]@{ project=$project; scenario=$activeScenario; fixtureEnv=(Split-Path $envFile -Leaf); iteration=$iteration; result='running'; cleanup='pending'; diagnosticsErrors=@() }
            # Check before entering the cleanup scope: never delete a pre-existing project.
            $initial = Find-Resources $project ($prefix + '-before')
            if ($initial.container.Count -or $initial.network.Count -or $initial.volume.Count) { throw 'Project resources already exist; refusing to reuse them' }
            $record.runs += $current
            [IO.File]::WriteAllText((Join-Path $results 'result.json'), ($record | ConvertTo-Json -Depth 12), $utf8)
            try {
                if ($activeScenario -in @('ip','ip-auth')) {
                    Invoke-DockerBounded -DockerArgs ($args + @('up','-d','--no-deps','--no-build','--pull','never','tester-allowed')) -TimeoutSeconds 90 -LogName ($prefix + '-allowed-start') | Out-Null
                    $address = Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','tester-allowed','ruby','-rsocket','-e','puts Socket.ip_address_list.select { |a| a.ipv4? && !a.ipv4_loopback? }.map(&:ip_address)')) -TimeoutSeconds 20 -LogName ($prefix + '-allowed-address')
                    $ip = $null
                    if (![Net.IPAddress]::TryParse($address.stdout.Trim(), [ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Expected exactly one IPv4 address for allowed tester' }
                    $environment.IT_ALLOWED_IP = $ip.ToString()
                    $current.allowedIp = $environment.IT_ALLOWED_IP
                    Set-ScenarioEnvironment $activeScenario
                    $runtimeConfig = Invoke-DockerBounded -DockerArgs ($args + @('config','--format','json')) -TimeoutSeconds 30 -LogName ($prefix + '-runtime-config')
                    Assert-IsolatedConfig ($runtimeConfig.stdout | ConvertFrom-Json)
                }
                Invoke-DockerBounded -DockerArgs ($args + @('run','--pull','never','--rm','--no-deps','-T','prepare')) -TimeoutSeconds 90 -LogName ($prefix + '-prepare') | Out-Null
                Invoke-DockerBounded -DockerArgs ($args + @('up','-d','--no-build','--pull','never','portal','echo')) -TimeoutSeconds 90 -LogName ($prefix + '-up') | Out-Null
                $net = Invoke-DockerBounded -DockerArgs @('network','inspect','--format','{{.Internal}}',($project + '_isolated')) -TimeoutSeconds 20 -LogName ($prefix + '-network-internal')
                if ($net.stdout.Trim() -ne 'true') { throw 'Created network is not internal' }
                $testArgs = @('run','--pull','never','--rm','--no-deps','-T')
                if ($activeScenario -eq 'never-ready') { $testArgs += @('-e','IT_EXPECTED_BODY=__intentional_readiness_failure__') }
                if ($activeScenario -in @('tls-policy','tls-chain','tls-expired')) {
                    $current.tls = @()
                    if ($activeScenario -eq 'tls-policy') {
                        if ($TLSMutation -eq 'disable-tls12') {
                            # Startup writes nginx.conf asynchronously after compose up.
                            # Prove the unmodified policy first, then acquire the same
                            # lock as setup/reconfig/renew before touching generated config.
                            $current.tlsBeforeMutation = Invoke-TLSContract $args ($prefix + '-before-mutation') 'check' $activeScenario
                            Hold-CertificateRenewal $args $prefix
                            $mutate = 'path="/etc/nginx/nginx.conf"; text=File.read(path); old="ssl_protocols TLSv1.2 TLSv1.3;"; raise "TLS mutation anchor missing" unless text.include?(old); File.write(path,text.sub(old,"ssl_protocols TLSv1.3;")); puts "mutation-tls12"'
                            Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','portal','ruby','-e',$mutate)) -TimeoutSeconds 20 -LogName ($prefix + '-mutation-tls12') | Out-Null
                            Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','portal','nginx','-t')) -TimeoutSeconds 20 -LogName ($prefix + '-mutation-nginx-test') | Out-Null
                            Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','portal','nginx','-s','reload')) -TimeoutSeconds 20 -LogName ($prefix + '-mutation-reload') | Out-Null
                            $current.mutationApplied = $TLSMutation
                        }
                        $current.tls += Invoke-TLSContract $args $prefix 'check' $activeScenario
                        if ($TLSMutation -ne 'none') { throw 'TLS mutation unexpectedly survived; this is not successful detection evidence' }
                    } else {
                        $current.tls += Invoke-TLSContract $args $prefix 'baseline' $activeScenario
                        Hold-CertificateRenewal $args $prefix
                        $variant = if ($activeScenario -eq 'tls-chain') { 'missing' } else { 'expired' }
                        Set-TLSFixture $args $prefix $variant
                        $current.tls += Invoke-TLSContract $args $prefix 'mutated' $activeScenario
                        Set-TLSFixture $args $prefix 'valid'
                        $current.tls += Invoke-TLSContract $args $prefix 'restored' $activeScenario
                    }
                } elseif ($activeScenario -in @('ip','ip-auth')) {
                    $roleEnv = @('-e',('IT_SCENARIO=' + $activeScenario),'-e',('IT_ALLOWED_IP=' + $environment.IT_ALLOWED_IP))
                    $allowed = Invoke-DockerBounded -DockerArgs ($args + @('exec','-T') + $roleEnv + @('-e','IT_ROLE=allowed','tester-allowed','ruby','/opt/it/ip_contracts.rb')) -TimeoutSeconds ($StartupTimeoutSeconds + 30) -LogName ($prefix + '-allowed-probe')
                    $allowedResult = ($allowed.stdout -split '\r?\n' | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
                    if ($allowedResult.result -ne 'passed' -or $allowedResult.role -ne 'allowed' -or $allowedResult.source_ip -ne $environment.IT_ALLOWED_IP) { throw 'Invalid allowed tester evidence' }
                    $current.allowed = $allowedResult
                    $testArgs += $roleEnv + @('-e','IT_ROLE=denied','tester','ruby','/opt/it/ip_contracts.rb')
                } elseif ($activeScenario -in @('persistence','renewal')) {
                    Invoke-DockerBounded -DockerArgs ($args + $testArgs + @('-e','IT_PHASE=before','tester','ruby','/opt/it/contracts.rb')) -TimeoutSeconds ($StartupTimeoutSeconds + 30) -LogName ($prefix + '-probe-before') | Out-Null
                    if ($activeScenario -eq 'persistence') {
                        Invoke-DockerBounded -DockerArgs ($args + @('up','-d','--no-deps','--force-recreate','--no-build','--pull','never','portal')) -TimeoutSeconds 90 -LogName ($prefix + '-recreate') | Out-Null
                    } else {
                        $renew = Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','-e','PATH=/command:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','portal','/command/with-contenv','/command/s6-envdir','-I','/var/lib/https-portal/dynamic-env','/bin/renew_certs')) -TimeoutSeconds 30 -LogName ($prefix + '-renew-skip')
                        if ($renew.stdout -notmatch 'Renewal skipped for portal\.test' -or $renew.stdout -match 'Renewed certs for') { throw 'I-07: expected renewal skip was not observed' }
                    }
                    $testArgs += @('-e','IT_PHASE=after','tester','ruby','/opt/it/contracts.rb')
                } elseif ($activeScenario -in @('local','never-ready')) {
                    $testArgs += 'tester'
                } else {
                    $testArgs += @('tester','ruby','/opt/it/contracts.rb')
                }
                if ($activeScenario -notin @('tls-policy','tls-chain','tls-expired')) {
                    $probe = Invoke-DockerBounded -DockerArgs ($args + $testArgs) -TimeoutSeconds ($StartupTimeoutSeconds + 30) -LogName ($prefix + '-probe')
                }
                if ($activeScenario -in @('ip','ip-auth')) {
                    $deniedResult = ($probe.stdout -split '\r?\n' | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
                    if ($deniedResult.result -ne 'passed' -or $deniedResult.role -ne 'denied' -or !$deniedResult.source_ip -or $deniedResult.source_ip -eq $environment.IT_ALLOWED_IP) { throw 'Invalid denied tester evidence' }
                    $current.denied = $deniedResult
                }
                if ($activeScenario -eq 'ca') {
                    $certPublic = Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','portal','openssl','x509','-in','/var/lib/https-portal/tls.test/local/signed.crt','-noout','-pubkey')) -TimeoutSeconds 20 -LogName ($prefix + '-cert-public-key')
                    $keyPublic = Invoke-DockerBounded -DockerArgs ($args + @('exec','-T','portal','openssl','pkey','-in','/var/lib/https-portal/tls.test/local/domain.key','-pubout')) -TimeoutSeconds 20 -LogName ($prefix + '-key-public-part')
                    if ($certPublic.stdout.Replace("`r`n","`n").Trim() -cne $keyPublic.stdout.Replace("`r`n","`n").Trim()) { throw 'I-05: certificate/private-key public parts differ' }
                    $current.keyMatches = $true
                }
                $current.result = 'passed'
            } catch { $current.result='failed'; $current.failure=$_.Exception.Message; $failure=$_.Exception.Message }
            finally {
                $diagnostics = [ordered]@{
                    ps=@('ps','-a','--format','service={{.Service}} state={{.State}} health={{.Health}} exit={{.ExitCode}}')
                    logs=@('logs','--no-color','--timestamps','--tail','300','portal','echo')
                    http=@('exec','-T','portal','cat',('/etc/nginx/conf.d/' + $activeHost + '.conf'))
                    https=@('exec','-T','portal','cat',('/etc/nginx/conf.d/' + $activeHost + '.ssl.conf'))
                    certificate=@('exec','-T','portal','openssl','x509','-in',('/var/lib/https-portal/' + $activeHost + '/local/signed.crt'),'-noout','-subject','-issuer','-dates','-fingerprint','-sha256')
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
          if ($failure) { break }
        }
        if ($failure) { throw $failure }
        $record.result = 'passed'
        $record.stage = 'complete'
        Write-Host ("Integration checks passed ($sequence isolated run(s), cleanup verified).")
    }
} catch { $record.result='failed'; $record.failure=$_.Exception.Message; $failure=$_.Exception.Message }
finally {
    $record.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    [IO.File]::WriteAllText((Join-Path $results 'result.json'), ($record | ConvertTo-Json -Depth 12), $utf8)
    Write-Host ('Evidence: dev/test-results/p2-integration/' + $runId)
}
if ($failure) { throw $failure }
