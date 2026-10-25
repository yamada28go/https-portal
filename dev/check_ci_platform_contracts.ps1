$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci-architecture.ps1')
function Reject([string]$Name,[scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw ('Expected rejection: '+$Name)};($Name+': passed')}
foreach($pair in @(@('x86_64','amd64'),@('X64','amd64'),@('aarch64','arm64'),@('ARM64','arm64'))){if((ConvertTo-CIArchitecture $pair[0]) -cne $pair[1]){throw 'Architecture alias mismatch'}}
'Architecture aliases: passed'
Assert-CINativePlatform amd64 X64 X64 linux x86_64 X64 ''
Assert-CINativePlatform arm64 Arm64 Arm64 linux aarch64 ARM64 'linux/arm64'
'Native amd64 and arm64: passed'
Reject 'Cross-architecture Docker Engine' {Assert-CINativePlatform arm64 Arm64 Arm64 linux x86_64 ARM64 ''}
Reject 'Emulated PowerShell process' {Assert-CINativePlatform arm64 Arm64 X64 linux aarch64 ARM64 ''}
Reject 'Wrong runner architecture' {Assert-CINativePlatform amd64 X64 X64 linux amd64 ARM64 ''}
Reject 'Forced Docker platform' {Assert-CINativePlatform arm64 Arm64 Arm64 linux aarch64 ARM64 'linux/amd64'}
Reject 'Non-Linux Engine' {Assert-CINativePlatform amd64 X64 X64 windows amd64 X64 ''}
Reject 'Unsupported ARM32' {ConvertTo-CIArchitecture armv7l}
$old=$env:CI_EXPECTED_ARCH
try {
 $env:CI_EXPECTED_ARCH='arm64'
 Assert-CIImageArchitecture arm64 'fixture'
 Reject 'Wrong prepared image' {Assert-CIImageArchitecture amd64 'fixture'}
 $env:CI_EXPECTED_ARCH=$null
 Assert-CIImageArchitecture amd64 'local fixture'
 'Local image flow unchanged without CI target: passed'
}finally{$env:CI_EXPECTED_ARCH=$old}
