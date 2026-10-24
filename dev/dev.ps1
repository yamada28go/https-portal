[CmdletBinding()]
param(
    [ValidateSet('Setup', 'Shell', 'Login', 'Codex', 'Test', 'Verify', 'Stop', 'Recreate')]
    [string]$Action = 'Shell',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)
$ErrorActionPreference = 'Stop'
$composePath = Join-Path $PSScriptRoot 'compose.dev.yaml'
function Invoke-DevDocker {
    param([string[]]$DockerArgs)
    & docker compose -p https-portal-dev -f $composePath @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed (exit $LASTEXITCODE): $($DockerArgs -join ' ')"
    }
}
# Resolve paths from dev; Compose mounts the parent checkout at /workspace.
Push-Location $PSScriptRoot
try {
    switch ($Action) {
        'Setup' {
            Invoke-DevDocker -DockerArgs @('config', '--quiet')
            $containerOS = & docker info --format '{{.OSType}}'
            if ($LASTEXITCODE -ne 0) { throw 'Cannot connect to Docker Desktop. Check that Linux containers are running and this terminal has access.' }
            if ($containerOS -ne 'linux') { throw 'Switch Docker Desktop to Linux containers.' }
            Invoke-DevDocker -DockerArgs @('build', 'dev')
            Invoke-DevDocker -DockerArgs @('up', '-d', 'dev')
            Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'dev-versions')
            Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'bundle', '_2.2.4_', 'install', '--frozen')
            Invoke-DevDocker -DockerArgs @('exec', '-T', 'dev', 'bundle', '_2.2.4_', 'check')
            Invoke-DevDocker -DockerArgs @('run', '--rm', 'test')
            Write-Host 'Setup and existing domain smoke test passed. Next from project root: .\dev\dev.ps1 Login'
        }
        'Shell' { Invoke-DevDocker -DockerArgs @('exec', 'dev', 'bash') }
        'Login' { Invoke-DevDocker -DockerArgs @('exec', 'dev', 'codex', 'login', '--device-auth') }
        'Codex' { Invoke-DevDocker -DockerArgs (@('exec', 'dev', 'codex-dev') + $ExtraArgs) }
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
}
finally { Pop-Location }
