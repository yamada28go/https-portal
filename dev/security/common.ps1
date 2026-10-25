# Shared primitives; no Docker calls are made merely by dot-sourcing this file.
function Write-SecurityJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 80), [Text.UTF8Encoding]::new($false))
}
function Read-SecurityJson([string]$Path) {
    try {
        # .NET CurrentDirectory can differ from PowerShell's current location.
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        [IO.File]::ReadAllText($resolved) | ConvertFrom-Json
    }
    catch { throw ('Cannot read JSON: ' + (Split-Path $Path -Leaf)) }
}
function Initialize-SecurityContext([string]$Results) {
    $script:securityResults = $Results
    $script:securityDocker = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
}
function ConvertTo-SecurityNativeArgument([string]$Value) {
    '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}
function Invoke-SecurityDocker {
    param([string[]]$DockerArgs,[string]$LogName,[int]$TimeoutSeconds=60,[switch]$AllowFailure)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:securityDocker
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($info.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in $DockerArgs) { $info.ArgumentList.Add($argument) }
    } else { $info.Arguments = ($DockerArgs | ForEach-Object { ConvertTo-SecurityNativeArgument $_ }) -join ' ' }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        Write-Host ("Running $LogName (limit ${TimeoutSeconds}s)")
        if (!$process.Start()) { throw 'Cannot start Docker CLI' }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $timedOut = $false
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $nextProgress = 30
        while (!$process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $timedOut=$true; break }
            if ($watch.Elapsed.TotalSeconds -ge $nextProgress) {
                Write-Host ("Still running $LogName ({0:N0}s elapsed)" -f $watch.Elapsed.TotalSeconds)
                $nextProgress += 30
            }
        }
        $watch.Stop()
        if ($timedOut) { try { $process.Kill() } catch {}; $null = $process.WaitForExit(5000) }
        $null = $outTask.Wait(5000); $null = $errTask.Wait(5000)
        $stdout = if ($outTask.IsCompleted) { $outTask.GetAwaiter().GetResult() } else { '[stdout capture incomplete]' }
        $stderr = if ($errTask.IsCompleted) { $errTask.GetAwaiter().GetResult() } else { '[stderr capture incomplete]' }
        $code = if ($timedOut) {124} elseif ($process.HasExited) {$process.ExitCode} else {125}
        [IO.File]::WriteAllText((Join-Path $script:securityResults ($LogName + '.stdout.log')), $stdout, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $script:securityResults ($LogName + '.stderr.log')), $stderr, [Text.UTF8Encoding]::new($false))
        if ($stderr) { Write-Host $stderr.TrimEnd() }
        if ($code -ne 0 -and !$AllowFailure) { throw "Docker operation failed: $LogName (exit $code, timeout=$timedOut)" }
        [pscustomobject]@{stdout=$stdout;stderr=$stderr;code=$code}
    } finally { $process.Dispose() }
}
function Get-SecurityContainerArgs {
    @('run','--rm','--pull','never','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true')
}
function Get-SecurityImage([string]$Reference,[string]$LogName) {
    if ([string]::IsNullOrWhiteSpace($Reference) -or $Reference.StartsWith('-') -or $Reference -match '[\s\x00-\x1f$#]') { throw 'Invalid local image reference' }
    $out = Invoke-SecurityDocker -DockerArgs @('image','inspect','--format','{"Id":{{json .Id}},"Os":{{json .Os}},"Architecture":{{json .Architecture}},"RepoDigests":{{json .RepoDigests}}}',$Reference) -LogName $LogName
    $image = $out.stdout | ConvertFrom-Json
    if ($image.Id -notmatch '^sha256:[0-9a-f]{64}$' -or $image.Os -ne 'linux') { throw 'A local Linux image with a valid ID is required' }
    $image
}
function Assert-SecurityDatabaseFresh($Metadata,[int]$MaxAgeHours=48,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$SchemaVersion=2) {
    if ($Metadata.Version -ne $SchemaVersion -or !$Metadata.UpdatedAt) { throw 'Unsupported or incomplete DB metadata' }
    if ($Metadata.UpdatedAt -is [DateTime]) { $updated = [DateTimeOffset]::new($Metadata.UpdatedAt) }
    else { $updated = [DateTimeOffset]::Parse([string]$Metadata.UpdatedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal) }
    $age = ($Now - $updated.ToUniversalTime()).TotalHours
    if ($age -lt (-5.0/60) -or $age -gt $MaxAgeHours) { throw 'DB is stale or has a future timestamp; prepare a new DB snapshot' }
}
function Get-SecurityDatabase([string]$ScannerId,[string]$Volume,[string]$Prefix,[ValidateSet('vulnerability','java')][string]$Kind='vulnerability') {
    if ($Volume -notmatch '^hp-trivy-db-[a-z0-9-]+$') { throw 'Unexpected DB volume name' }
    $directory = if ($Kind -eq 'java') {'java-db'} else {'db'}
    $databaseFile = if ($Kind -eq 'java') {'trivy-java.db'} else {'trivy.db'}
    $base = (Get-SecurityContainerArgs) + @('--mount',('type=volume,source=' + $Volume + ',target=/cache,readonly'))
    $meta = Invoke-SecurityDocker -DockerArgs ($base + @('--entrypoint','/bin/cat',$ScannerId,('/cache/' + $directory + '/metadata.json'))) -LogName ($Prefix + '-metadata')
    $hash = Invoke-SecurityDocker -DockerArgs ($base + @('--entrypoint','/bin/sh',$ScannerId,'-c',('sha256sum /cache/' + $directory + '/' + $databaseFile + ' /cache/' + $directory + '/metadata.json'))) -LogName ($Prefix + '-hashes')
    $files = [ordered]@{}
    $pattern = '^([0-9a-f]{64})\s+/cache/' + [regex]::Escape($directory) + '/(' + [regex]::Escape($databaseFile) + '|metadata\.json)$'
    foreach ($line in ($hash.stdout -split '\r?\n' | Where-Object { $_.Trim() })) {
        if ($line -notmatch $pattern) { throw 'Invalid DB checksum output' }
        $files[$Matches[2]] = $Matches[1]
    }
    if ($files.Count -ne 2) { throw 'DB files are missing' }
    [pscustomobject]@{metadata=($meta.stdout | ConvertFrom-Json);files=$files}
}
function Assert-SecurityDatabaseIdentity($Actual,$Expected,[ValidateSet('vulnerability','java')][string]$Kind='vulnerability') {
    $databaseFile = if ($Kind -eq 'java') {'trivy-java.db'} else {'trivy.db'}
    foreach ($name in @($databaseFile,'metadata.json')) {
        $a = $Actual.files.PSObject.Properties[$name]
        $e = $Expected.files.PSObject.Properties[$name]
        # Fresh snapshots use ordered dictionaries; persisted receipts use objects.
        $av = if ($Actual.files -is [Collections.IDictionary]) {$Actual.files[$name]} elseif ($a) {$a.Value}
        $ev = if ($Expected.files -is [Collections.IDictionary]) {$Expected.files[$name]} elseif ($e) {$e.Value}
        if (!$av -or !$ev -or $av -cne $ev) { throw 'DB snapshot changed or does not match the preparation receipt' }
    }
}
# Docker's selected ID can be a manifest/index digest with the containerd store.
# Trivy reports the config digest. Derive it from the exact pinned export,
# rather than accepting whatever ID the report supplies.
# Share this run's Linux bind files through their existing groups.
# cap-drop ALL prevents root from bypassing host-owned 0600 permissions.
function Initialize-SecurityBindAccess([string]$InputDirectory,[string]$Results) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Unix) {
        return [pscustomobject]@{mode='desktop';dockerArgs=@();groupIds=@()}
    }
    $archive = Join-Path $InputDirectory 'image.tar'
    $outputs = @((Join-Path $Results 'vulnerabilities.raw.json'),(Join-Path $Results 'sbom.cdx.json'))
    foreach ($path in $outputs) {
        if (Test-Path -LiteralPath $path) { throw 'Refusing to overwrite a preexisting scanner output' }
        [IO.File]::WriteAllText($path,'',[Text.UTF8Encoding]::new($false))
        [IO.File]::SetUnixFileMode($path,[IO.UnixFileMode]432) # 0660
    }
    [IO.File]::SetUnixFileMode($Results,[IO.UnixFileMode]1528) # 02770, setgid
    [IO.File]::SetUnixFileMode($InputDirectory,[IO.UnixFileMode]488) # 0750
    [IO.File]::SetUnixFileMode($archive,[IO.UnixFileMode]416) # 0640
    $stat = (Get-Command stat -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $paths = @($Results,$InputDirectory,$archive) + $outputs
    $groups = @(& $stat '-c' '%g' '--' @paths)
    if ($LASTEXITCODE -ne 0 -or $groups.Count -ne $paths.Count) { throw 'Cannot determine scanner bind file groups' }
    $containerArgs = @()
    foreach ($group in @($groups | Sort-Object -Unique)) {
        if ([string]$group -notmatch '^[0-9]{1,10}$') { throw 'Invalid scanner bind file group' }
        $containerArgs += @('--group-add',[string]$group)
    }
    [pscustomobject]@{mode='unix-shared-groups';dockerArgs=$containerArgs;groupIds=@($groups | Sort-Object -Unique)}
}
function Get-SecurityArchiveIdentity([string]$ScannerId,[string]$InputDirectory,[string[]]$AccessArgs=@()) {
    $base = (Get-SecurityContainerArgs) + $AccessArgs + @('--tmpfs','/tmp:rw,nosuid,nodev,size=32m','--mount',('type=bind,source=' + $InputDirectory + ',target=/input,readonly'))
    $out = Invoke-SecurityDocker -DockerArgs ($base + @('--entrypoint','/bin/tar',$ScannerId,'-xOf','/input/image.tar','manifest.json')) -LogName 'archive-manifest'
    try { $manifest = @($out.stdout | ConvertFrom-Json) } catch { throw 'Invalid Docker archive manifest JSON' }
    if ($manifest.Count -ne 1) { throw 'A Docker archive with exactly one image manifest is required' }
    $config = [string]$manifest[0].Config
    if ($config -notmatch '^(?:([0-9a-f]{64})\.json|blobs/sha256/([0-9a-f]{64}))$') { throw 'Unsupported Docker archive config path' }
    $expected = if ($Matches[1]) {$Matches[1]} else {$Matches[2]}
    # Do not log config contents: it may contain private environment/history.
    $command = 'tar -xOf /input/image.tar ' + $config + ' > /tmp/config.json && sha256sum /tmp/config.json'
    $hash = Invoke-SecurityDocker -DockerArgs ($base + @('--entrypoint','/bin/sh',$ScannerId,'-c',$command)) -LogName 'archive-config-hash'
    if ($hash.stdout.Trim() -notmatch '^([0-9a-f]{64})\s+/tmp/config\.json$' -or $Matches[1] -cne $expected) { throw 'Docker archive config content does not match its digest' }
    [pscustomobject]@{configImageId=('sha256:' + $expected);configPath=$config}
}
function Get-SecurityReportSummary($Report,[string]$ImageId) {
    if ($Report.SchemaVersion -ne 2) { throw 'Unsupported scan report schema' }
    if ($Report.ArtifactType -ne 'container_image') { throw 'Scan report is not a container image report' }
    if ($Report.Metadata.ImageID -cne $ImageId) { throw 'Scan report image ID differs from the verified archive config digest' }
    $counts = [ordered]@{UNKNOWN=0;LOW=0;MEDIUM=0;HIGH=0;CRITICAL=0}
    $packages = 0
    foreach ($result in $Report.Results) {
        $packages += @($result.Packages | Where-Object { $_ }).Count
        foreach ($finding in $result.Vulnerabilities) {
            if (!$finding.VulnerabilityID -or !$finding.PkgName) { throw 'Incomplete vulnerability finding' }
            $severity = ([string]$finding.Severity).ToUpperInvariant()
            if (!$counts.Contains($severity)) { $severity = 'UNKNOWN' }
            $counts[$severity]++
        }
    }
    if ($packages -le 0) { throw 'Scan report contains no package inventory' }
    [pscustomobject]@{packageEntries=$packages;severityCounts=$counts;enforcement='report-only';thresholdEnabled=$false}
}
function Assert-SecuritySbom($Bom,[string]$ImageId) {
    if ($Bom.bomFormat -ne 'CycloneDX' -or !$Bom.specVersion -or @($Bom.components | Where-Object {$_}).Count -eq 0) { throw 'Invalid or empty CycloneDX SBOM' }
    $ids = @($Bom.metadata.component.properties | Where-Object {$_.name -eq 'aquasecurity:trivy:ImageID' -and $_.value -ceq $ImageId})
    if ($ids.Count -ne 1) { throw 'SBOM is not linked to the scanned image ID' }
}
function Remove-SecurityImageConfiguration($Report) {
    $Report.Metadata.PSObject.Properties.Remove('ImageConfig')
}