[CmdletBinding()]
param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Mode = 'release',
    [string]$BuildName,
    [string]$BuildNumber,
    [string]$OutputDirectory,
    [string]$Flutter = 'flutter',
    [switch]$SplitPerAbi,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'release\android'
}
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot $OutputDirectory
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

if (-not (Get-Command $Flutter -ErrorAction SilentlyContinue)) {
    throw "错误：找不到 Flutter：$Flutter"
}

Set-Location $projectRoot
if ($Clean) {
    & $Flutter clean
    if ($LASTEXITCODE -ne 0) { throw '错误：flutter clean 失败。' }
}

$arguments = @('build', 'apk', "--$Mode")
if (-not [string]::IsNullOrWhiteSpace($BuildName)) { $arguments += "--build-name=$BuildName" }
if (-not [string]::IsNullOrWhiteSpace($BuildNumber)) { $arguments += "--build-number=$BuildNumber" }
if ($SplitPerAbi) { $arguments += '--split-per-abi' }

& $Flutter @arguments
if ($LASTEXITCODE -ne 0) { throw '错误：Android APK 构建失败。' }

$apkDirectory = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
$apkPattern = if ($SplitPerAbi) { "app-*-$Mode.apk" } else { "app-$Mode.apk" }
$apkFiles = @(Get-ChildItem -LiteralPath $apkDirectory -Filter $apkPattern -File)
if ($apkFiles.Count -eq 0) { throw "错误：构建完成但没有找到 $apkPattern。" }

$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^\s]+)')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }
$safeVersion = $version -replace '[^A-Za-z0-9._+-]', '_'

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputs = foreach ($apk in $apkFiles) {
    $suffix = if ($SplitPerAbi) {
        ($apk.BaseName -replace '^app-', '' -replace "-$([regex]::Escape($Mode))$", '')
    } else {
        'universal'
    }
    $destination = Join-Path $OutputDirectory "bookstore_management_system-$safeVersion-$Mode-$suffix.apk"
    Copy-Item -LiteralPath $apk.FullName -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$destination.sha256" -Value "$hash  $([System.IO.Path]::GetFileName($destination))" -Encoding ascii
    [pscustomobject]@{ Apk = $destination; Sha256 = $hash }
}

Write-Host "`n构建完成"
Write-Host "  模式：$Mode"
foreach ($output in $outputs) {
    Write-Host "  APK：$($output.Apk)"
    Write-Host "  SHA-256：$($output.Sha256)"
}
if ($Mode -eq 'release') {
    Write-Warning '当前 Android release 构建仍使用项目内配置的 debug 签名，仅适合测试安装，不适合应用商店或正式分发。'
}
