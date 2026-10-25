$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'badges.ps1')
$checks=@()
function Reject([string]$Name,[scriptblock]$Action){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};if(!$failed){throw ('Expected rejection: '+$Name)};$script:checks+=($Name+': passed')}
function Clone($Value){$Value | ConvertTo-Json -Depth 12 -Compress | ConvertFrom-Json}
$id='sha256:'+('a'*64);$config='sha256:'+('b'*64);$commit='c'*40
$summary=[pscustomobject]@{mode='report-only';thresholdEnabled=$false;imageId=$id;scanImageId=$config;severityCounts=[pscustomobject]@{CRITICAL=12;HIGH=135}}
$result=[pscustomobject]@{result='collected';stage='complete';cleanup='passed';imageId=$id;scanImageId=$config;reportImageId=$config;finishedUtc='2026-10-25T07:17:34Z';summary=@{severityCounts=@{CRITICAL=12;HIGH=135}}}
$data=New-SecurityBadgeData $summary $result 'owner/repository' 'refs/heads/master' $commit '100' '1'
$files=Get-SecurityBadgeFiles $data
$critical=$files['critical.json']|ConvertFrom-Json;$high=$files['high.json']|ConvertFrom-Json
if($critical.message -cne '12' -or $critical.color -ne 'red' -or $high.message -cne '135' -or $high.color -ne 'orange'){throw 'Positive counts rendered incorrectly'}
$checks+='Critical/High counts and colors: passed'
$zero=Clone $data;$zero.severityCounts.CRITICAL=0;$zero.severityCounts.HIGH=0
$f=Get-SecurityBadgeFiles $zero
if(($f['critical.json']|ConvertFrom-Json).message -cne '0' -or ($f['high.json']|ConvertFrom-Json).color -ne 'brightgreen'){throw 'Zero counts rendered incorrectly'}
$checks+='Zero counts remain explicit: passed'
foreach($value in @(-1,1.5,'12',$true,$null)){$bad=Clone $data;$bad.severityCounts.CRITICAL=$value;Reject ('Invalid count '+[string]$value) {Get-SecurityBadgeFiles $bad}}
$bad=Clone $result;$bad.result='failed';Reject 'Failed collection' {New-SecurityBadgeData $summary $bad 'owner/repository' 'refs/heads/master' $commit '100' '1'}
$bad=Clone $result;$bad.cleanup='failed';Reject 'Failed cleanup' {New-SecurityBadgeData $summary $bad 'owner/repository' 'refs/heads/master' $commit '100' '1'}
$bad=Clone $summary;$bad.scanImageId='sha256:'+('d'*64);Reject 'Summary image mismatch' {New-SecurityBadgeData $bad $result 'owner/repository' 'refs/heads/master' $commit '100' '1'}
$bad=Clone $summary;$bad.severityCounts.HIGH=1;Reject 'Summary count mismatch' {New-SecurityBadgeData $bad $result 'owner/repository' 'refs/heads/master' $commit '100' '1'}
$bad=Clone $data;$bad|Add-Member -NotePropertyName ImageConfig -NotePropertyValue @{Env=@('PRIVATE=do-not-publish')};Reject 'Unapproved public metadata refused' {Get-SecurityBadgeFiles $bad}
$bad=Clone $data;$bad.runUrl='https://unrelated.example/run';Reject 'Unrelated source URL refused' {Get-SecurityBadgeFiles $bad}
$pr=New-SecurityBadgeData $summary $result 'owner/repository' 'refs/pull/1/merge' $commit '100' '1'
$checks+='PR can generate artifacts without publication: passed'
$script:expectedCommit=$commit
$originalApi=(Get-Item Function:Invoke-SecurityBadgeGitHub).ScriptBlock
try {
 function Invoke-SecurityBadgeGitHub([string]$Method,[string]$Path,$Body=$null,[switch]$AllowNotFound){
  $script:calls+=@{method=$Method;path=$Path;body=$Body}
  if($script:mode -eq 'api-failure'){throw 'Simulated API failure'}
  if($Path -match '/git/ref/heads/(master|work%2Fyamada%2Fadd-ut)$'){return @{object=@{sha=$(if($script:mode -eq 'advanced'){'e'*40}else{$script:expectedCommit})}}}
  if($Path -match '/git/ref/heads/security-badges$'){if($script:mode -eq 'create'){return $null};return @{object=@{sha='f'*40}}}
  if($Method -eq 'GET' -and $Path -match '/git/commits/'){return @{tree=@{sha='1'*40}}}
  if($Method -eq 'GET' -and $Path -match '/git/trees/'){
   $names=if($script:mode -eq 'collision'){@('README.md')}else{@('critical.json','high.json','latest.json')}
   return @{tree=@($names|ForEach-Object {@{path=$_;type='blob';sha='2'*40}})}
  }
  if($Method -eq 'GET' -and $Path -match '/git/blobs/'){
   $previous=Clone $data;if($script:mode -eq 'source-switch'){$previous.ref='refs/heads/work/yamada/add-ut'};$previous.runId=if($script:mode -eq 'newer'){'101'}else{'99'};$previous.runUrl='https://github.com/owner/repository/actions/runs/'+$previous.runId
   return @{encoding='base64';content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($previous|ConvertTo-Json -Depth 8 -Compress)))}
  }
  if($Method -eq 'POST' -and $Path -match '/git/trees$'){
   if(@($Body.tree).Count -ne 3){throw 'Unapproved public files'}
   foreach($entry in $Body.tree){if($entry.path -notin @('critical.json','high.json','latest.json')){throw 'Unexpected published artifact'}}
   return @{sha='3'*40}
  }
  if($Method -eq 'POST' -and $Path -match '/git/commits$'){return @{sha='4'*40}}
  if($Method -eq 'POST' -and $Path -match '/git/refs$'){if($Body.ref -ne 'refs/heads/security-badges'){throw 'Unexpected ref'};return @{}}
  if($Method -eq 'PATCH' -and $Path -match '/git/refs/heads/security-badges$'){if($Body.force -ne $false){throw 'Force push attempted'};return @{}}
  throw ('Unexpected API operation: '+$Method+' '+$Path)
 }
 foreach($case in @('create','update','advanced','newer')){
  $script:mode=$case;$script:calls=@()
  $out=Publish-SecurityBadgeData $data 'owner/repository' 'master' $commit
  $expected=if($case -in @('advanced','newer')){'skipped'}else{'published'}
  if($out -cne $expected){throw ('Unexpected publish result '+$case)}
  if($expected -eq 'skipped' -and @($script:calls|Where-Object {$_.method -ne 'GET'}).Count){throw 'Stale run wrote public data'}
  if($case -eq 'create' -and @($script:calls|Where-Object {$_.path -match '/git/commits$'})[0].body.parents.Count -ne 0){throw 'New badge branch is not orphaned'}
  $checks+=($case+' publication: passed')
 }
 $script:mode='update';$script:calls=@()
 $work=Clone $data;$work.ref='refs/heads/work/yamada/add-ut'
 $out=Publish-SecurityBadgeData $work 'owner/repository' 'work/yamada/add-ut' $commit
 if($out -cne 'published' -or !@($script:calls|Where-Object {$_.path -match '/git/ref/heads/work%2Fyamada%2Fadd-ut$'}).Count){throw 'Current branch was not resolved dynamically'}
 $checks+='Work branch publication with automatic source identity: passed'
 $script:mode='source-switch';$script:calls=@();$out=Publish-SecurityBadgeData $data 'owner/repository' 'master' $commit
 if($out -cne 'published'){throw 'Post-merge default branch publication failed'}
 $checks+='Default branch publication after source branch change: passed'
 Reject 'Mismatched execution branch refused' {Publish-SecurityBadgeData $work 'owner/repository' 'master' $commit}
 $sink=Clone $data;$sink.ref='refs/heads/security-badges'
 Reject 'Generated data branch cannot republish' {Publish-SecurityBadgeData $sink 'owner/repository' 'security-badges' $commit}
 $script:mode='collision';Reject 'Unrelated branch preserved' {Publish-SecurityBadgeData $data 'owner/repository' 'master' $commit}
 $script:mode='api-failure';Reject 'API failure visible' {Publish-SecurityBadgeData $data 'owner/repository' 'master' $commit}
 $script:mode='create';$script:calls=@();Reject 'PR publication refused' {Publish-SecurityBadgeData $pr 'owner/repository' 'master' $commit}
 if($script:calls.Count){throw 'PR reached publication API'}
 Reject 'Wrong repository publication refused' {Publish-SecurityBadgeData $data 'another/repository' 'master' $commit}
} finally {Set-Item Function:Invoke-SecurityBadgeGitHub $originalApi}
$checks
