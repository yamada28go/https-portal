[CmdletBinding()]
param(
    [ValidateSet('Setup', 'Shell', 'Login', 'Codex', 'Test', 'Verify', 'Stop', 'Recreate', 'P1')]
    [string]$Action = 'Shell',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)
$ErrorActionPreference = 'Stop'
$composePath = Join-Path $PSScriptRoot 'compose.dev.yaml'
function Invoke-DockerNative {
    param([string[]]$DockerArgs, [switch]$Interactive)
    $dockerExecutable = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    # Windows PowerShell 5.1 converts redirected native stderr into ErrorRecords.
    # Docker progress on stderr is normal; only a nonzero exit means failure.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    if ($Interactive) {
        & $dockerExecutable @DockerArgs
    }
    else {
        & $dockerExecutable @DockerArgs 2>&1 | ForEach-Object { $_.ToString() }
    }
    $dockerExitCode = $LASTEXITCODE
    if ($dockerExitCode -ne 0) {
        throw "Docker command failed (exit $dockerExitCode): $($DockerArgs -join ' ')"
    }
}
function Invoke-DevDocker {
    param([string[]]$DockerArgs, [switch]$Interactive)
    Invoke-DockerNative -DockerArgs (@('compose', '-p', 'https-portal-dev', '-f', $composePath) + $DockerArgs) -Interactive:$Interactive
}
# Absolute Compose path resolves mounts without changing the caller's location.
switch ($Action) {
    'Setup' {
        Invoke-DevDocker -DockerArgs @('config', '--quiet')
        $containerOS = Invoke-DockerNative -DockerArgs @('info', '--format', '{{.OSType}}')
        if ($containerOS -ne 'linux') { throw 'Switch Docker Desktop to Linux containers.' }
        Invoke-DevDocker -DockerArgs @('build', 'dev')
        Invoke-DevDocker -DockerArgs @('up', '-d', 'dev')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'dev-versions')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'bundle', '_2.2.4_', 'install', '--frozen')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'bundle', '_2.2.4_', 'check')
        Invoke-DevDocker -DockerArgs @('run', '--rm', 'test')
        Write-Host 'Setup and P1 unit tests passed. Next from project root: .\dev\dev.ps1 Login'
    }
    'Shell' { Invoke-DevDocker -Interactive -DockerArgs @('exec', 'dev', 'bash') }
    'Login' { Invoke-DevDocker -Interactive -DockerArgs @('exec', 'dev', 'codex', 'login', '--device-auth') }
    'Codex' { Invoke-DevDocker -Interactive -DockerArgs (@('exec', 'dev', 'codex-dev') + $ExtraArgs) }
    'P1' { Invoke-DevDocker -DockerArgs @('run', '--rm', 'test', 'bundle', 'exec', 'ruby', 'dev/check_p1.rb') }
    'Test' { Invoke-DevDocker -DockerArgs (@('run', '--rm', 'test') + $ExtraArgs) }
    'Verify' {
        Invoke-DevDocker -DockerArgs @('config', '--quiet')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'dev-versions')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'sh', '-c', 'test -w /workspace && test -w /bundle && test -w /home/dev/.codex && test ! -S /var/run/docker.sock')
        Invoke-DevDocker -DockerArgs @('run', '--rm', 'test', 'sh', '-c', 'test ! -e /home/dev/.codex/auth.json && test ! -S /var/run/docker.sock')
        Invoke-DevDocker -DockerArgs @('run', '--rm', 'test')
    }
    'Stop' { Invoke-DevDocker -DockerArgs @('down') }
    'Recreate' {
        Invoke-DevDocker -DockerArgs @('down')
        Invoke-DevDocker -DockerArgs @('up', '-d', 'dev')
        Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'bundle', '_2.2.4_', 'check')
        Invoke-DevDocker -DockerArgs @('run', '--rm', 'test')
    }
}
