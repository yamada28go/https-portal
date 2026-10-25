# No network or writes occur merely by dot-sourcing this file.
function Assert-SecurityBadgeData($Data) {
    $allowed=@('schemaVersion','publisher','reportOnly','repository','ref','commit','runId','runAttempt','runUrl','scanFinishedUtc','imageId','scanImageId','severityCounts')
    $keys=if($Data -is [Collections.IDictionary]){@($Data.Keys)}else{@($Data.PSObject.Properties.Name)}
    if(@($keys | Where-Object {$_ -notin $allowed}).Count -or $keys.Count -ne $allowed.Count){throw 'Unexpected public badge metadata fields'}
    if ($Data.schemaVersion -ne 1 -or $Data.publisher -cne 'https-portal-security-counts/v1' -or $Data.reportOnly -ne $true) { throw 'Invalid security badge data schema' }
    if ($Data.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $Data.ref -notmatch '^refs/(?:heads|tags|pull)/[^\s]+$' -or $Data.commit -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') { throw 'Invalid badge source identity' }
    if ([string]$Data.runId -notmatch '^[1-9][0-9]*$' -or [string]$Data.runAttempt -notmatch '^[1-9][0-9]*$') { throw 'Invalid badge source run' }
    foreach ($name in @('imageId','scanImageId')) { if ($Data.$name -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Invalid badge image digest' } }
    foreach ($name in @('CRITICAL','HIGH')) {
        $value=$Data.severityCounts.$name
        if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or $value -lt 0 -or $value -gt [int]::MaxValue -or [decimal]$value -ne [decimal][Math]::Floor([double]$value)) { throw 'Badge counts must be nonnegative integers' }
    }
    $null=[DateTimeOffset]::Parse([string]$Data.scanFinishedUtc,[Globalization.CultureInfo]::InvariantCulture)
    $expected='https://github.com/'+$Data.repository+'/actions/runs/'+$Data.runId
    if ($Data.runUrl -cne $expected) { throw 'Invalid badge run URL' }
}
function New-SecurityBadgeData($Summary,$Result,[string]$Repository,[string]$Ref,[string]$Commit,[string]$RunId,[string]$RunAttempt) {
    if ($Result.result -ne 'collected' -or $Result.stage -ne 'complete' -or $Result.cleanup -ne 'passed' -or $Summary.mode -ne 'report-only' -or $Summary.thresholdEnabled -ne $false) { throw 'Only a completed report-only collection may generate count badges' }
    if ($Summary.imageId -cne $Result.imageId -or $Summary.scanImageId -cne $Result.scanImageId -or $Result.reportImageId -cne $Summary.scanImageId) { throw 'Badge summary/result image mismatch' }
    foreach ($name in @('CRITICAL','HIGH')) { if ($Summary.severityCounts.$name -ne $Result.summary.severityCounts.$name) { throw 'Badge summary/result counts mismatch' } }
    $data=[pscustomobject][ordered]@{
        schemaVersion=1;publisher='https-portal-security-counts/v1';reportOnly=$true
        repository=$Repository;ref=$Ref;commit=$Commit;runId=$RunId;runAttempt=$RunAttempt
        runUrl=('https://github.com/'+$Repository+'/actions/runs/'+$RunId)
        scanFinishedUtc=([DateTimeOffset]::Parse([string]$Result.finishedUtc).ToUniversalTime().ToString('o'))
        imageId=$Summary.imageId;scanImageId=$Summary.scanImageId
        severityCounts=[pscustomobject]@{CRITICAL=$Summary.severityCounts.CRITICAL;HIGH=$Summary.severityCounts.HIGH}
    }
    Assert-SecurityBadgeData $data
    $data
}
function Get-SecurityBadgeFiles($Data) {
    Assert-SecurityBadgeData $Data
    $files=[ordered]@{}
    foreach($name in @('CRITICAL','HIGH')) {
        $count=[int]$Data.severityCounts.$name
        $color=if($count -eq 0){'brightgreen'}elseif($name -eq 'CRITICAL'){'red'}else{'orange'}
        $badge=[ordered]@{schemaVersion=1;label=($name.Substring(0,1)+$name.Substring(1).ToLowerInvariant());message=$count.ToString([Globalization.CultureInfo]::InvariantCulture);color=$color}
        $files[$name.ToLowerInvariant()+'.json']=$badge | ConvertTo-Json -Compress
    }
    $files['latest.json']=$Data | ConvertTo-Json -Depth 8 -Compress
    $files
}
function Write-SecurityBadgeFiles($Data,[string]$Directory) {
    $files=Get-SecurityBadgeFiles $Data
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    foreach($name in $files.Keys) { [IO.File]::WriteAllText((Join-Path $Directory $name),$files[$name]+"`n",[Text.UTF8Encoding]::new($false)) }
}
function Invoke-SecurityBadgeGitHub([string]$Method,[string]$Path,$Body=$null,[switch]$AllowNotFound) {
    if (!$env:GITHUB_TOKEN) { throw 'GITHUB_TOKEN is required for badge publication' }
    $params=@{Method=$Method;Uri=('https://api.github.com'+$Path);Headers=@{Authorization=('Bearer '+$env:GITHUB_TOKEN);Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2026-03-10'};ErrorAction='Stop'}
    if($null -ne $Body){$params.Body=$Body | ConvertTo-Json -Depth 12 -Compress;$params.ContentType='application/json'}
    try { Invoke-RestMethod @params }
    catch {
        $status=0
        if($_.Exception.Response){$status=[int]$_.Exception.Response.StatusCode}
        if($AllowNotFound -and $status -eq 404){return $null}
        throw ('Badge GitHub API request failed: '+$Method+' '+$Path+' (HTTP '+$status+')')
    }
}
function Publish-SecurityBadgeData($Data,[string]$Repository,[string]$SourceBranch,[string]$HeadSha) {
    Assert-SecurityBadgeData $Data
    if($Data.repository -cne $Repository -or $Data.commit -cne $HeadSha -or $Data.ref -cne ('refs/heads/'+$SourceBranch) -or $SourceBranch -ceq 'security-badges') { throw 'Count badges must match the scanned source branch' }
    $base='/repos/'+$Repository
    $head=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/ref/heads/'+[Uri]::EscapeDataString($SourceBranch))
    if($head.object.sha -cne $HeadSha){Write-Host 'Skip badge publication: source branch has advanced.';return 'skipped'}
    $old=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/ref/heads/security-badges') -AllowNotFound
    if($old) {
        $commit=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/commits/'+$old.object.sha)
        $tree=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/trees/'+$commit.tree.sha)
        $paths=@($tree.tree | ForEach-Object {$_.path} | Sort-Object)
        if($tree.truncated -eq $true -or ($paths -join ',') -cne 'critical.json,high.json,latest.json' -or @($tree.tree | Where-Object {$_.type -ne 'blob'}).Count){throw 'Refusing to overwrite an unrelated security-badges branch'}
        $latest=@($tree.tree | Where-Object path -eq 'latest.json')[0]
        $blob=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/blobs/'+$latest.sha)
        if($blob.encoding -ne 'base64'){throw 'Unexpected published metadata encoding'}
        $previous=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob.content)) | ConvertFrom-Json
        Assert-SecurityBadgeData $previous
        if($previous.repository -cne $Repository){throw 'Published badge source mismatch'}
        if([long]$previous.runId -gt [long]$Data.runId -or ([long]$previous.runId -eq [long]$Data.runId -and [long]$previous.runAttempt -ge [long]$Data.runAttempt)){Write-Host 'Skip badge publication: run is already published or superseded.';return 'skipped'}
    }
    $files=Get-SecurityBadgeFiles $Data
    $entries=@()
    foreach($name in $files.Keys){$entries+=@{path=$name;mode='100644';type='blob';content=($files[$name]+"`n")}}
    $tree=Invoke-SecurityBadgeGitHub 'POST' ($base+'/git/trees') @{tree=$entries}
    $body=@{message=('Update security counts from run '+$Data.runId+' attempt '+$Data.runAttempt);tree=$tree.sha}
    if($old){$body.parents=@($old.object.sha)}else{$body.parents=@()}
    $commit=Invoke-SecurityBadgeGitHub 'POST' ($base+'/git/commits') $body
    # Recheck before moving the publication ref. Never force-push.
    $head=Invoke-SecurityBadgeGitHub 'GET' ($base+'/git/ref/heads/'+[Uri]::EscapeDataString($SourceBranch))
    if($head.object.sha -cne $HeadSha){Write-Host 'Skip badge publication: source branch advanced during preparation.';return 'skipped'}
    if($old){$null=Invoke-SecurityBadgeGitHub 'PATCH' ($base+'/git/refs/heads/security-badges') @{sha=$commit.sha;force=$false}}
    else{$null=Invoke-SecurityBadgeGitHub 'POST' ($base+'/git/refs') @{ref='refs/heads/security-badges';sha=$commit.sha}}
    Write-Host ('Published Critical/High counts from '+$Data.runUrl)
    'published'
}
