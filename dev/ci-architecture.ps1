# Shared architecture checks; no commands run merely by dot-sourcing this file.
function ConvertTo-CIArchitecture([string]$Value) {
    switch ($Value.ToLowerInvariant()) {
        {$_ -in @('amd64','x86_64','x64')} {return 'amd64'}
        {$_ -in @('arm64','aarch64')} {return 'arm64'}
        default {throw ('Unsupported CI architecture: '+$Value)}
    }
}
function Assert-CIImageArchitecture([string]$Architecture,[string]$Description='image') {
    if (!$env:CI_EXPECTED_ARCH) {return}
    $expected=ConvertTo-CIArchitecture $env:CI_EXPECTED_ARCH
    if ((ConvertTo-CIArchitecture $Architecture) -cne $expected) {throw ($Description+' architecture differs from CI_EXPECTED_ARCH='+$expected)}
}
function Assert-CINativePlatform([string]$Expected,[string]$HostArchitecture,[string]$ProcessArchitecture,[string]$EngineOS,[string]$EngineArchitecture,[string]$RunnerArchitecture,[string]$DefaultPlatform) {
    $expectedArch=ConvertTo-CIArchitecture $Expected
    foreach($value in @($HostArchitecture,$ProcessArchitecture,$EngineArchitecture)) {
        if((ConvertTo-CIArchitecture $value) -cne $expectedArch){throw 'Runner/process/Docker architecture must match the native CI target'}
    }
    if($EngineOS -cne 'linux'){throw 'Native CI requires a Linux Docker Engine'}
    if($RunnerArchitecture -and (ConvertTo-CIArchitecture $RunnerArchitecture) -cne $expectedArch){throw 'RUNNER_ARCH does not match the CI target'}
    if($DefaultPlatform -and $DefaultPlatform -cne ('linux/'+$expectedArch)){throw 'DOCKER_DEFAULT_PLATFORM overrides the native CI target'}
}
