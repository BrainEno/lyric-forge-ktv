param([string]$Flutter = 'flutter')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$snapshot = Join-Path ([System.IO.Path]::GetTempPath()) ('flutter-deps-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
Push-Location $repoRoot
try {
    $trackedInputs = @('pubspec.lock', 'analysis_options.yaml')
    foreach ($file in $trackedInputs) {
        Copy-Item -LiteralPath $file -Destination (Join-Path $snapshot $file)
    }

    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get --enforce-lockfile failed with exit code $LASTEXITCODE"
    }

    $modified = $false
    foreach ($file in $trackedInputs) {
        $before = (Get-FileHash -LiteralPath (Join-Path $snapshot $file) -Algorithm SHA256).Hash
        $after = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if ($before -ne $after) {
            Write-Host "ERROR: Flutter dependency resolution unexpectedly modified $file."
            & git --no-pager diff -- $file
            $modified = $true
        }
    }

    if ($modified) {
        throw 'Dependency resolution must not rewrite committed lock or analyzer configuration files.'
    }
    Write-Host 'Flutter dependency resolution is reproducible; tracked inputs remained unchanged.'
} finally {
    Pop-Location
    Remove-Item -LiteralPath $snapshot -Recurse -Force -ErrorAction SilentlyContinue
}
