param([string]$Flutter = 'flutter')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Fail-PinnedSdkCheck([string]$Message) {
    throw "Pinned Flutter SDK check failed: $Message Use the Flutter version declared in $repoRoot/.fvmrc."
}

$config = Get-Content -LiteralPath (Join-Path $repoRoot '.fvmrc') -Raw | ConvertFrom-Json
$expectedFlutter = [string]$config.flutter
if ($expectedFlutter -notmatch '^\d+\.\d+\.\d+$') {
    Fail-PinnedSdkCheck '.fvmrc must define a semantic Flutter version such as 3.47.7.'
}

$flutterCommand = Get-Command $Flutter -ErrorAction SilentlyContinue
if ($null -eq $flutterCommand) {
    Fail-PinnedSdkCheck "Flutter executable not found: $Flutter."
}
$flutterInfoJson = & $Flutter --version --machine 2>$null
if ($LASTEXITCODE -ne 0 -or -not $flutterInfoJson) {
    Fail-PinnedSdkCheck "Unable to query Flutter version from $Flutter."
}
$flutterInfo = ($flutterInfoJson -join "`n") | ConvertFrom-Json
$actualFlutter = [string]$flutterInfo.frameworkVersion
$expectedDart = [string]$flutterInfo.dartSdkVersion
if ($actualFlutter -ne $expectedFlutter) {
    Fail-PinnedSdkCheck "Expected Flutter $expectedFlutter, found $actualFlutter."
}
if ([string]::IsNullOrWhiteSpace($expectedDart)) {
    Fail-PinnedSdkCheck 'flutter --version --machine did not report dartSdkVersion.'
}

$dartCommand = Get-Command dart -ErrorAction SilentlyContinue
if ($null -eq $dartCommand) {
    Fail-PinnedSdkCheck 'Dart executable not found on PATH.'
}
$dartVersionOutput = (& dart --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail-PinnedSdkCheck 'Unable to query dart --version.'
}
$match = [regex]::Match($dartVersionOutput, 'Dart SDK version: (\d+\.\d+\.\d+)')
if (-not $match.Success) {
    Fail-PinnedSdkCheck "Unable to parse dart --version output: $dartVersionOutput"
}
$actualDart = $match.Groups[1].Value
if ($actualDart -ne $expectedDart) {
    Fail-PinnedSdkCheck "Flutter $actualFlutter bundles Dart $expectedDart, but PATH resolves Dart $actualDart ($($dartCommand.Source))."
}

Write-Host "Pinned toolchain verified: Flutter $actualFlutter / Dart $actualDart" -ForegroundColor Green
