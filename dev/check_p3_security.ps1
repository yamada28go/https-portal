[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PortalImage,
    [Parameter(Mandatory=$true)][string]$PreparationFile,
    [ValidateRange(1,720)][int]$MaxDatabaseAgeHours=48,
    [ValidateRange(1,720)][int]$MaxJavaDatabaseAgeHours=168
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'security/common.ps1')
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ').ToLowerInvariant() + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p3-security/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$inputDir = Join-Path $results '.input'
New-Item -ItemType Directory -Path $inputDir -Force | Out-Null
$archive = Join-Path $inputDir 'image.tar'
$rawPath = Join-Path $results 'vulnerabilities.raw.json'
$record = [ordered]@{runId=$runId;startedUtc=[DateTimeOffset]::UtcNow.ToString('o');result='running';stage='preflight';mode='offline-report-only';requestedImage=$PortalImage;thresholdEnabled=$false;cleanup='pending'}
$workVolume = 'hp-trivy-work-' + $runId
$workCreated = $false
$failure = $null
if ($env:GITHUB_ACTIONS -eq 'true') { $record.github=@{event=$env:GITHUB_EVENT_NAME;runId=$env:GITHUB_RUN_ID;runAttempt=$env:GITHUB_RUN_ATTEMPT;expectedSha=$env:GITHUB_SHA} }
try {
    Initialize-SecurityContext $results
    $settings = Read-SecurityJson (Join-Path $PSScriptRoot 'security/trivy-settings.json')
    $receipt = Read-SecurityJson $PreparationFile
    if ($receipt.result -ne 'prepared' -or $receipt.stage -ne 'complete' -or $receipt.scannerReference -cne $settings.image -or $receipt.scannerVersion -cne $settings.version) { throw 'A successful preparation receipt for the pinned scanner is required' }
    if (!$receipt.javaDatabase) { throw 'Preparation receipt has no Java DB snapshot; rerun dev/prepare_p3_security.ps1' }
    if ($receipt.databaseVolume -notmatch '^hp-trivy-db-[a-z0-9-]+$') { throw 'Unexpected DB volume in preparation receipt' }
    $scanner = Get-SecurityImage $settings.image 'scanner-inspect'
    if ($scanner.Id -cne $receipt.scannerImageId) { throw 'Prepared scanner ID mismatch' }
    $image = Get-SecurityImage $PortalImage 'image-inspect'
    $record.imageId=$image.Id
    $record.imagePlatform=$image.Os + '/' + $image.Architecture
    $record.repoDigests=$image.RepoDigests
    $record.scannerReference=$settings.image
    $record.scannerVersion=$settings.version
    $record.scannerImageId=$scanner.Id
    $record.preparationRunId=$receipt.runId
    $record.maxDatabaseAgeHours=$MaxDatabaseAgeHours
    $record.maxJavaDatabaseAgeHours=$MaxJavaDatabaseAgeHours
    $purpose = Invoke-SecurityDocker -DockerArgs @('volume','inspect','--format','{{index .Labels "org.https-portal.purpose"}}',$receipt.databaseVolume) -LogName 'db-volume'
    if ($purpose.stdout.Trim() -ne 'p3-security-db') { throw 'Prepared DB volume is missing its purpose label' }
    $before = Get-SecurityDatabase $scanner.Id $receipt.databaseVolume 'db-before'
    Assert-SecurityDatabaseFresh $before.metadata $MaxDatabaseAgeHours
    Assert-SecurityDatabaseIdentity $before $receipt.database
    $record.database=$before
    $javaBefore = Get-SecurityDatabase $scanner.Id $receipt.databaseVolume 'java-db-before' 'java'
    Assert-SecurityDatabaseFresh -Metadata $javaBefore.metadata -MaxAgeHours $MaxJavaDatabaseAgeHours -SchemaVersion 1
    Assert-SecurityDatabaseIdentity $javaBefore $receipt.javaDatabase 'java'
    $record.javaDatabase=$javaBefore
    $record.stage='image-export'
    Invoke-SecurityDocker -DockerArgs @('image','save','--output',$archive,$image.Id) -LogName 'image-export' -TimeoutSeconds 600 | Out-Null
    if (!(Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -le 0) { throw 'Image archive was not created' }
    $record.imageArchiveSha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $record.stage='archive-identity'
    $identity = Get-SecurityArchiveIdentity $scanner.Id $inputDir
    $record.archiveIdentity=$identity
    $record.scanImageId=$identity.configImageId
    $oldWork = Invoke-SecurityDocker -DockerArgs @('volume','inspect',$workVolume) -LogName 'work-before' -AllowFailure
    if ($oldWork.code -eq 0) { throw 'Refusing to reuse a scanner work volume' }
    $created = Invoke-SecurityDocker -DockerArgs @('volume','create','--label','org.https-portal.purpose=p3-security-work',$workVolume) -LogName 'work-create'
    $workCreated=$true
    if ($created.stdout.Trim() -cne $workVolume) { throw 'Unexpected scanner work volume' }
    $record.stage='vulnerability-scan'
    $base = (Get-SecurityContainerArgs) + @('--tmpfs','/tmp:rw,nosuid,nodev,size=256m','--env','TMPDIR=/scratch/tmp','--mount',('type=bind,source=' + $inputDir + ',target=/input,readonly'),'--mount',('type=bind,source=' + $results + ',target=/output'),'--mount',('type=volume,source=' + $receipt.databaseVolume + ',target=/prepared,readonly'),'--mount',('type=volume,source=' + $workVolume + ',target=/scratch'))
    $entry = 'mkdir -p /scratch/cache/db /scratch/cache/java-db /scratch/tmp && cp /prepared/db/trivy.db /prepared/db/metadata.json /scratch/cache/db/ && cp /prepared/java-db/trivy-java.db /prepared/java-db/metadata.json /scratch/cache/java-db/ && exec trivy "$@"'
    $scanArgs = @('--entrypoint','/bin/sh',$scanner.Id,'-c',$entry,'trivy-offline','image','--config','','--input','/input/image.tar','--cache-dir','/scratch/cache','--skip-db-update','--skip-java-db-update','--skip-check-update','--offline-scan','--skip-version-check','--disable-telemetry','--no-progress','--scanners','vuln','--list-all-pkgs','--ignorefile','/dev/null','--severity','UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL','--exit-code','0','--timeout','15m','--format','json','--output','/output/vulnerabilities.raw.json')
    Invoke-SecurityDocker -DockerArgs ($base + $scanArgs) -LogName 'vulnerability-scan' -TimeoutSeconds 1200 | Out-Null
    $report = Read-SecurityJson $rawPath
    # Keep only a validated digest in diagnostics, never raw image configuration.
    if ([string]$report.Metadata.ImageID -cmatch '^sha256:[0-9a-f]{64}$') { $record.reportImageId=[string]$report.Metadata.ImageID }
    $summary = Get-SecurityReportSummary $report $identity.configImageId
    # Supplemental inventory identifies binary/script coverage gaps, without
    # claiming environment version strings prove the actual downloaded bytes.
    $external = @()
    foreach ($item in @(@{name='s6-overlay';key='S6_OVERLAY_VERSION'},@{name='docker-gen';key='DOCKER_GEN_VERSION'},@{name='acme-tiny';key='ACME_TINY_VERSION'})) {
        $match = @($report.Metadata.ImageConfig.config.Env | Where-Object {$_ -like ($item.key + '=*')})
        $declared = if ($match.Count -eq 1) {$match[0].Substring($item.key.Length + 1)} else {$null}
        $external += [ordered]@{name=$item.name;declaredVersion=$declared;source='image-config-env';artifactHashVerified=$false;vulnerabilityCoverage='not-established'}
    }
    Remove-SecurityImageConfiguration $report
    Write-SecurityJson (Join-Path $results 'vulnerabilities.json') $report
    Write-SecurityJson (Join-Path $results 'external-components.json') @{components=$external;note='Supplemental declared versions only. Confirm binary/script hashes and automatic SBOM coverage before claiming full coverage.'}
    $record.stage='sbom-conversion'
    Invoke-SecurityDocker -DockerArgs ($base + @($scanner.Id,'convert','--config','','--ignorefile','/dev/null','--format','cyclonedx','--scanners','vuln','--output','/output/sbom.cdx.json','/output/vulnerabilities.json')) -LogName 'sbom-conversion' -TimeoutSeconds 300 | Out-Null
    $bom = Read-SecurityJson (Join-Path $results 'sbom.cdx.json')
    Assert-SecuritySbom $bom $identity.configImageId
    $after = Get-SecurityDatabase $scanner.Id $receipt.databaseVolume 'db-after'
    Assert-SecurityDatabaseIdentity $after $before
    $javaAfter = Get-SecurityDatabase $scanner.Id $receipt.databaseVolume 'java-db-after' 'java'
    Assert-SecurityDatabaseIdentity $javaAfter $javaBefore 'java'
    $record.summary=$summary
    $record.sbomComponents=@($bom.components).Count
    $summaryOut = [ordered]@{mode='report-only';imageId=$image.Id;scanImageId=$identity.configImageId;archiveIdentity=$identity;imageArchiveSha256=$record.imageArchiveSha256;scannerImageId=$scanner.Id;scannerVersion=$settings.version;database=$before;javaDatabase=$javaBefore;os=$report.Metadata.OS;packageEntries=$summary.packageEntries;severityCounts=$summary.severityCounts;sbomComponents=$record.sbomComponents;thresholdEnabled=$false;fullComponentCoverageEstablished=$false}
    Write-SecurityJson (Join-Path $results 'summary.json') $summaryOut
    $files = @('vulnerabilities.json','sbom.cdx.json','summary.json','external-components.json')
    $hashes = @($files | ForEach-Object {(Get-FileHash -LiteralPath (Join-Path $results $_) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_})
    [IO.File]::WriteAllText((Join-Path $results 'artifacts.sha256'),($hashes -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    $record.result='collected'
    $record.stage='complete'
} catch { $failure=$_.Exception.Message;$record.result='failed';$record.failure=$failure }
finally {
    $cleanupErrors = @()
    if ($workCreated) {
        try { Invoke-SecurityDocker -DockerArgs @('volume','rm',$workVolume) -LogName 'work-cleanup' -TimeoutSeconds 60 | Out-Null }
        catch { $cleanupErrors += 'Scanner work volume cleanup failed' }
    }
    foreach ($temporary in @($archive,$rawPath)) {
        try { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
        catch { $cleanupErrors += ('Temporary file cleanup failed: ' + (Split-Path $temporary -Leaf)) }
    }
    $record.cleanup = if ($cleanupErrors.Count) { 'failed' } else { 'passed' }
    if ($cleanupErrors.Count) {
        $record.cleanupErrors=$cleanupErrors
        $record.result='failed'
        if (!$failure) { $failure='Security scratch cleanup failed' }
    }
    $record.finishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-SecurityJson (Join-Path $results 'result.json') $record
    Write-Host ('Evidence: dev/test-results/p3-security/' + $runId)
}
if ($failure) { throw $failure }
Write-Host 'Security evidence collected (report-only; findings are not a severity gate).'