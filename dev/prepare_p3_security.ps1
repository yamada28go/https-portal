[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'security/common.ps1')
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ').ToLowerInvariant() + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$results = Join-Path $PSScriptRoot ('test-results/p3-security-preparation/' + $runId)
New-Item -ItemType Directory -Path $results -Force | Out-Null
$receiptPath = Join-Path $results 'prepared.json'
$settings = Read-SecurityJson (Join-Path $PSScriptRoot 'security/trivy-settings.json')
$record = [ordered]@{runId=$runId;startedUtc=[DateTimeOffset]::UtcNow.ToString('o');result='running';stage='engine';scannerReference=$settings.image;scannerVersion=$settings.version;databaseVolume=('hp-trivy-db-' + $runId)}
try {
    Initialize-SecurityContext $results
    $os = Invoke-SecurityDocker -DockerArgs @('info','--format','{{.OSType}}') -LogName 'engine'
    if ($os.stdout.Trim() -ne 'linux') { throw 'A reachable Linux Docker Engine is required' }
    if ($settings.image -notmatch '^aquasec/trivy:[0-9.]+@sha256:[a-f0-9]{64}$') { throw 'Scanner must be pinned to an official image digest' }
    $record.stage = 'scanner-pull'
    Invoke-SecurityDocker -DockerArgs @('pull',$settings.image) -LogName 'scanner-pull' -TimeoutSeconds 900 | Out-Null
    $image = Get-SecurityImage $settings.image 'scanner-inspect'
    $record.scannerImageId = $image.Id
    $record.scannerPlatform = $image.Os + '/' + $image.Architecture
    $version = Invoke-SecurityDocker -DockerArgs ((Get-SecurityContainerArgs) + @($image.Id,'--version')) -LogName 'scanner-version'
    if ($version.stdout.Trim() -cne ('Version: ' + $settings.version)) { throw 'Scanner CLI version differs from the pinned release' }
    $record.stage = 'database-download'
    $existing = Invoke-SecurityDocker -DockerArgs @('volume','inspect',$record.databaseVolume) -LogName 'db-before' -AllowFailure
    if ($existing.code -eq 0) { throw 'Refusing to update an existing DB volume' }
    $created = Invoke-SecurityDocker -DockerArgs @('volume','create','--label','org.https-portal.purpose=p3-security-db',$record.databaseVolume) -LogName 'db-create'
    if ($created.stdout.Trim() -cne $record.databaseVolume) { throw 'Unexpected created DB volume' }
    # Only this explicit preparation command has network access. No socket/source mounts.
    $args = @('run','--rm','--pull','never','--network','bridge','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--tmpfs','/tmp:rw,nosuid,nodev,size=256m','--mount',('type=volume,source=' + $record.databaseVolume + ',target=/cache'),'--entrypoint','/bin/sh',$image.Id,'-c','mkdir -p /cache/tmp && export TMPDIR=/cache/tmp && exec trivy "$@"','trivy-prepare','image','--config','','--download-db-only','--cache-dir','/cache','--skip-version-check','--disable-telemetry','--no-progress','--timeout','12m')
    Invoke-SecurityDocker -DockerArgs $args -LogName 'db-download' -TimeoutSeconds 900 | Out-Null
    $record.stage = 'java-database-download'
    $javaArgs = @($args | ForEach-Object { if ($_ -ceq '--download-db-only') {'--download-java-db-only'} else {$_} })
    Invoke-SecurityDocker -DockerArgs $javaArgs -LogName 'java-db-download' -TimeoutSeconds 900 | Out-Null
    $database = Get-SecurityDatabase $image.Id $record.databaseVolume 'db'
    Assert-SecurityDatabaseFresh $database.metadata
    $record.database = $database
    $javaDatabase = Get-SecurityDatabase $image.Id $record.databaseVolume 'java-db' 'java'
    Assert-SecurityDatabaseFresh -Metadata $javaDatabase.metadata -MaxAgeHours 168 -SchemaVersion 1
    $record.javaDatabase = $javaDatabase
    $record.result = 'prepared'
    $record.stage = 'complete'
} catch { $record.result='failed';$record.failure=$_.Exception.Message;throw }
finally {
    $record.finishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-SecurityJson $receiptPath $record
    Write-Host ('Evidence: dev/test-results/p3-security-preparation/' + $runId)
}
# Only this object goes to the success stream; logs use Write-Host.
[pscustomobject]@{PreparationFile=$receiptPath;ScannerImageId=$record.scannerImageId;DatabaseVolume=$record.databaseVolume}