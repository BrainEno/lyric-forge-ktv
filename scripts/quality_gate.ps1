param(
    [switch]$SkipPubGet,
    [switch]$AnalyzeOnly,
    [switch]$TestOnly,
    [string[]]$TestPath = @()
)

$ErrorActionPreference = 'Stop'

if ($AnalyzeOnly -and $TestOnly) {
    throw 'Only one quality-gate mode may be selected.'
}
if ($AnalyzeOnly -and $TestPath.Count -gt 0) {
    throw '-TestPath cannot be used with -AnalyzeOnly.'
}

$mode = 'all'
if ($AnalyzeOnly) {
    $mode = 'analyze'
}
elseif ($TestOnly) {
    $mode = 'test'
}

function Invoke-CheckedStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Get-QualityGateBranch {
    if ($env:CM_BRANCH) { return $env:CM_BRANCH }
    if ($env:GITHUB_HEAD_REF) { return $env:GITHUB_HEAD_REF }
    if ($env:GITHUB_REF_NAME) { return $env:GITHUB_REF_NAME }
    try {
        return (& git branch --show-current 2>$null).Trim()
    }
    catch {
        return ''
    }
}

$branch = Get-QualityGateBranch
$commit = 'unknown'
try {
    $commit = (& git rev-parse HEAD 2>$null).Trim()
}
catch {
    $commit = 'unknown'
}
$branchLabel = 'detached-or-unknown'
if ($branch) {
    $branchLabel = $branch
}

Write-Host 'Quality gate provenance:' -ForegroundColor DarkCyan
Write-Host "  branch: $branchLabel"
Write-Host "  commit: $commit"
Write-Host "  mode: $mode"
if ($TestPath.Count -gt 0) {
    Write-Host '  targeted tests:'
    foreach ($path in $TestPath) {
        Write-Host "    - $path"
    }
}
else {
    Write-Host '  targeted tests: none (full suite when tests run)'
}

if (-not $SkipPubGet) {
    Invoke-CheckedStep -Name 'flutter pub get' -Command { flutter pub get }
}

# Analyze the application and its test surface. packages/desktop_multi_window is a
# vendored dependency; its example/ is a separate demo app with optional upstream
# dependencies and must not become part of this application's quality gate.
if ($mode -eq 'all' -or $mode -eq 'analyze') {
    Invoke-CheckedStep -Name 'flutter analyze lib test' -Command {
        flutter analyze --no-pub lib test
    }
}

if ($mode -eq 'all' -or $mode -eq 'test') {
    if ($TestPath.Count -gt 0) {
        $testArgs = @('test', '--no-pub', '--reporter', 'expanded') + $TestPath
        Invoke-CheckedStep -Name 'targeted flutter test' -Command {
            flutter @testArgs
        }
    }
    else {
        Invoke-CheckedStep -Name 'flutter test' -Command {
            flutter test --no-pub --reporter expanded
        }
    }
}

Write-Host ""
Write-Host "Repository quality gate ($mode) passed." -ForegroundColor Green
