$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$checks=@()
function Expect-Rejection([string]$Name,[scriptblock]$Action) {
    $failed=$false
    try { & $Action } catch { $failed=$true }
    if (!$failed) { throw ('Expected rejection: '+$Name) }
    $script:checks += ($Name+': passed')
}
$id='sha256:'+('a'*64)
$report=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json')
$s=Get-SecurityReportSummary $report $id
if($s.packageEntries -ne 1 -or $s.severityCounts.HIGH -ne 1 -or $s.thresholdEnabled -ne $false){throw 'Report summary mismatch'}
$checks+='High finding stays report-only: passed'
$report.Results[0].Vulnerabilities[0].Severity='CRITICAL'
$s=Get-SecurityReportSummary $report $id
if($s.severityCounts.CRITICAL -ne 1 -or $s.thresholdEnabled -ne $false){throw 'Critical incorrectly enforced'}
$checks+='Critical finding stays report-only: passed'
Expect-Rejection 'Wrong scan image' {Get-SecurityReportSummary $report ('sha256:'+('b'*64))}
$empty=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json');$empty.Results=@()
Expect-Rejection 'Empty package report' {Get-SecurityReportSummary $empty $id}
$bad=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json');$bad.Results[0].Vulnerabilities[0].VulnerabilityID=''
Expect-Rejection 'Malformed finding' {Get-SecurityReportSummary $bad $id}
$now=[DateTimeOffset]::Parse('2026-10-25T00:00:00Z')
Assert-SecurityDatabaseFresh @{Version=2;UpdatedAt='2026-10-24T00:00:00Z'} 48 $now
$checks+='Fresh DB: passed'
Expect-Rejection 'Stale DB' {Assert-SecurityDatabaseFresh @{Version=2;UpdatedAt='2026-10-22T00:00:00Z'} 48 $now}
Expect-Rejection 'Future DB' {Assert-SecurityDatabaseFresh @{Version=2;UpdatedAt='2026-10-25T01:00:00Z'} 48 $now}
Expect-Rejection 'Unsupported DB schema' {Assert-SecurityDatabaseFresh @{Version=3;UpdatedAt='2026-10-24T00:00:00Z'} 48 $now}
$a=@{files=@{'trivy.db'=('a'*64);'metadata.json'=('b'*64)}}
$b=@{files=@{'trivy.db'=('a'*64);'metadata.json'=('b'*64)}}
Assert-SecurityDatabaseIdentity $a $b
$checks+='Identical DB: passed'
$b.files['trivy.db']='c'*64
Expect-Rejection 'Changed DB' {Assert-SecurityDatabaseIdentity $a $b}
$b.files.Remove('trivy.db')
Expect-Rejection 'Missing DB hash' {Assert-SecurityDatabaseIdentity $a $b}
$bom=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/sbom.cdx.json')
Assert-SecuritySbom $bom $id
$checks+='Native Trivy converted SBOM: passed'
Expect-Rejection 'SBOM wrong image' {Assert-SecuritySbom $bom ('sha256:'+('b'*64))}
$bom.components=@()
Expect-Rejection 'Empty SBOM' {Assert-SecuritySbom $bom $id}
$brokenFile=[IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($brokenFile,'{"private":"do-not-echo",BROKEN')
$failed=$false;try {Read-SecurityJson $brokenFile}catch{$failed=$true;if($_.Exception.Message.Contains('do-not-echo')){throw 'Raw report leaked through parse exception'}}
if(!$failed){throw 'Broken JSON accepted'}
$checks+='Malformed JSON has sanitized error: passed'
Remove-Item -LiteralPath $brokenFile -Force
$redacted=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json')
$redacted.Metadata | Add-Member -NotePropertyName ImageConfig -NotePropertyValue @{config=@{Env=@('PRIVATE=do-not-echo')}}
Remove-SecurityImageConfiguration $redacted
if (($redacted | ConvertTo-Json -Depth 30).Contains('do-not-echo')) {throw 'Image environment was not removed'}
$checks+='Image configuration redaction: passed'
$checks
Assert-SecurityDatabaseFresh -Metadata @{Version=1;UpdatedAt='2026-10-22T00:00:00Z'} -MaxAgeHours 168 -Now $now -SchemaVersion 1
$checks+='Fresh Java DB (separate schema/age): passed'
Expect-Rejection 'Stale Java DB' {Assert-SecurityDatabaseFresh -Metadata @{Version=1;UpdatedAt='2026-10-17T00:00:00Z'} -MaxAgeHours 168 -Now $now -SchemaVersion 1}
Expect-Rejection 'Wrong Java DB schema' {Assert-SecurityDatabaseFresh -Metadata @{Version=2;UpdatedAt='2026-10-24T00:00:00Z'} -Now $now -SchemaVersion 1}
$javaA=@{files=@{'trivy-java.db'=('a'*64);'metadata.json'=('b'*64)}}
$javaB=($javaA | ConvertTo-Json | ConvertFrom-Json)
Assert-SecurityDatabaseIdentity $javaA $javaB 'java'
$checks+='Java DB receipt roundtrip: passed'
$javaB.files.'trivy-java.db'='c'*64
Expect-Rejection 'Changed Java DB' {Assert-SecurityDatabaseIdentity $javaA $javaB 'java'}
$javaB.files.PSObject.Properties.Remove('trivy-java.db')
Expect-Rejection 'Missing Java DB hash' {Assert-SecurityDatabaseIdentity $javaA $javaB 'java'}
$checks | Select-Object -Last 6

$report=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json')
$report.SchemaVersion=3
Expect-Rejection 'Wrong report schema' {Get-SecurityReportSummary $report $id}
$report.SchemaVersion=2;$report.ArtifactType='filesystem'
Expect-Rejection 'Wrong report artifact type' {Get-SecurityReportSummary $report $id}
$checks | Select-Object -Last 2

$originalDocker=(Get-Item Function:Invoke-SecurityDocker).ScriptBlock
try {
    function Invoke-SecurityDocker {
        param([string[]]$DockerArgs,[string]$LogName)
        $script:contractSeenDockerArgs=$DockerArgs
        if ($DockerArgs[([Array]::IndexOf($DockerArgs,'--network')+1)] -ne 'none' -or $DockerArgs -notcontains '--read-only') {throw 'Archive inspection lost isolation'}
        if ($LogName -eq 'archive-manifest') {return [pscustomobject]@{stdout=$script:contractManifest}}
        if ($LogName -eq 'archive-config-hash') {return [pscustomobject]@{stdout=$script:contractConfigHash}}
        throw 'Unexpected archive inspection operation'
    }
    $script:contractManifest='[{"Config":"'+('a'*64)+'.json"}]'
    $script:contractConfigHash=('a'*64)+'  /tmp/config.json'
    $identity=Get-SecurityArchiveIdentity $id 'fixture-input'
    if ($identity.configImageId -cne $id) {throw 'Classic archive config ID mismatch'}
    $checks+='Classic archive config ID: passed'
    $script:contractManifest='[{"Config":"blobs/sha256/'+('a'*64)+'"}]'
    $identity=Get-SecurityArchiveIdentity $id 'fixture-input'
    if ($identity.configImageId -cne $id) {throw 'OCI archive config ID mismatch'}
    $checks+='OCI archive config ID: passed'
    $null=Get-SecurityArchiveIdentity $id 'fixture-input' @('--group-add','1234')
    if($script:contractSeenDockerArgs[([Array]::IndexOf($script:contractSeenDockerArgs,'--group-add')+1)] -ne '1234' -or $script:contractSeenDockerArgs -contains '--cap-add'){throw 'Archive supplemental group propagation failed'}
    $checks+='Bind group propagation preserves capability limits: passed'
    $script:contractConfigHash=('b'*64)+'  /tmp/config.json'
    Expect-Rejection 'Archive config content digest mismatch' {Get-SecurityArchiveIdentity $id 'fixture-input'}
    $script:contractManifest='[{"Config":"../../private"}]'
    Expect-Rejection 'Archive config path traversal' {Get-SecurityArchiveIdentity $id 'fixture-input'}
    $script:contractManifest='[{},{}]'
    Expect-Rejection 'Ambiguous multiple image archive' {Get-SecurityArchiveIdentity $id 'fixture-input'}
    $script:contractManifest='{BROKEN'
    Expect-Rejection 'Broken archive manifest' {Get-SecurityArchiveIdentity $id 'fixture-input'}
    $checks | Select-Object -Last 7
} finally {
    Set-Item Function:Invoke-SecurityDocker $originalDocker
    Remove-Variable contractManifest,contractConfigHash,contractSeenDockerArgs -Scope Script -ErrorAction SilentlyContinue
}

# Resolve paths against PowerShell's location, not the process directory.
$originalProcessDirectory=[Environment]::CurrentDirectory
Push-Location $PSScriptRoot
try {
    [Environment]::CurrentDirectory=[IO.Path]::GetTempPath()
    $relativeReport=Read-SecurityJson './fixtures/report.json'
    $absoluteReport=Read-SecurityJson (Join-Path $PSScriptRoot 'fixtures/report.json')
    if($relativeReport.Metadata.ImageID -cne $id -or $absoluteReport.Metadata.ImageID -cne $id){throw 'JSON path resolution mismatch'}
    'Relative and absolute JSON paths with different process directory: passed'
} finally {
    Pop-Location
    [Environment]::CurrentDirectory=$originalProcessDirectory
}
# Exercise real Unix modes on Linux CI; desktop keeps its bind behavior.
$bindRoot=Join-Path ([IO.Path]::GetTempPath()) ('hp-security-bind-'+[Guid]::NewGuid().ToString('N'))
$bindInput=Join-Path $bindRoot '.input'
New-Item -ItemType Directory -Path $bindInput -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $bindInput 'image.tar'),'synthetic archive permission fixture')
try {
    $access=Initialize-SecurityBindAccess $bindInput $bindRoot
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Unix) {
        if($access.mode -ne 'unix-shared-groups' -or $access.dockerArgs.Count -lt 2){throw 'Unix bind groups missing'}
        foreach($path in @($bindRoot,$bindInput,(Join-Path $bindInput 'image.tar'),(Join-Path $bindRoot 'vulnerabilities.raw.json'),(Join-Path $bindRoot 'sbom.cdx.json'))){
            if(([int][IO.File]::GetUnixFileMode($path) -band 7) -ne 0){throw 'Scanner bind permissions exposed to Other'}
        }
        if(([int][IO.File]::GetUnixFileMode((Join-Path $bindInput 'image.tar')) -band 32) -eq 0){throw 'Archive group read missing'}
        foreach($name in @('vulnerabilities.raw.json','sbom.cdx.json')){
            $path=Join-Path $bindRoot $name
            if(([int][IO.File]::GetUnixFileMode($path) -band 48) -ne 48){throw 'Output group read/write missing'}
            [IO.File]::WriteAllText($path,'{"host":"can-read-write"}')
            $null=Read-SecurityJson $path
        }
        'Linux archive/output permissions and supplemental groups: passed'
    } elseif($access.mode -ne 'desktop' -or $access.dockerArgs.Count -ne 0){throw 'Desktop bind behavior changed'}
    else {
        # Reproduce hidden-directory cleanup on Windows as well as Unix CI.
        [IO.File]::SetAttributes($bindInput,([IO.File]::GetAttributes($bindInput) -bor [IO.FileAttributes]::Hidden))
        'Desktop bind permissions unchanged: passed'
    }
} finally {
    foreach($path in @((Join-Path $bindInput 'image.tar'),(Join-Path $bindRoot 'vulnerabilities.raw.json'),(Join-Path $bindRoot 'sbom.cdx.json'))){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
    # .input is hidden on Unix; Force is required by the PowerShell provider.
    Remove-Item -LiteralPath $bindInput -Force
    Remove-Item -LiteralPath $bindRoot -Force
}

if ((Test-Path -LiteralPath $bindInput) -or (Test-Path -LiteralPath $bindRoot)) {throw 'Bind permission fixture cleanup incomplete'}
'Bind permission fixture cleanup: passed'
