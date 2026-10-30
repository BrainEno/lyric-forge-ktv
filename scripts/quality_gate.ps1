param(
    [switch]$SkipPubGet,
    [switch]$AnalyzeOnly,
    [switch]$TestOnly,
    [switch]$SkipDocs,
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

# Verify that PATH resolves the exact Flutter/Dart pair pinned in .fvmrc.
Invoke-CheckedStep -Name 'verify pinned Flutter/Dart SDK' -Command {
    & "$PSScriptRoot\check_flutter_sdk.ps1"
}

# Fail fast on documentation-contract errors before running the analyzer and
# full test suite, rather than discovering a stale work log after all tests.
if ($mode -eq 'all' -and -not $SkipDocs) {
    Invoke-CheckedStep -Name 'work log preflight (before analyze/tests)' -Command {
        dart tool/work_log.dart check
    }
}

if (-not $SkipPubGet) {
    Invoke-CheckedStep -Name 'reproducible Flutter dependency resolution' -Command {
        & "$PSScriptRoot\resolve_flutter_dependencies.ps1"
    }
}

# Analyze the application and its test surface. packages/desktop_multi_window is a
# vendored dependency; its example/ is a separate demo app with optional upstream
# dependencies and must not become part of this application's quality gate.
# Style infos stay non-fatal, matching the CI workflows; errors and warnings
# still fail the gate.
if ($mode -eq 'all' -or $mode -eq 'analyze') {
    Invoke-CheckedStep -Name 'flutter analyze lib test' -Command {
        flutter analyze --no-pub --no-fatal-infos lib test
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
