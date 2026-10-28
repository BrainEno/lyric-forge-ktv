[CmdletBinding()]
param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$AvdName = 'pixel_4_api33',
    [int]$ApiLevel = 33,
    [string]$DeviceProfile = 'pixel',
    [int]$BootTimeoutSeconds = 240,
    [switch]$ColdBoot,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-WithError([string]$Message) {
    throw "错误：$Message"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    Stop-WithError '找不到 Flutter。请先把 Flutter SDK 的 bin 目录加入 PATH。'
}

if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    $configuredSdkLine = & flutter config --list 2>$null | Select-String 'android-sdk:\s*(.+)$' | Select-Object -First 1
    if ($configuredSdkLine) {
        $AndroidSdk = $configuredSdkLine.Matches[0].Groups[1].Value.Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($AndroidSdk) -and (Test-Path 'D:\AndroidSDK')) {
    $AndroidSdk = 'D:\AndroidSDK'
}
if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    Stop-WithError '未找到 Android SDK。可通过 -AndroidSdk 指定路径。'
}
$AndroidSdk = [System.IO.Path]::GetFullPath($AndroidSdk)

$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\avdmanager.bat'
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'
foreach ($requiredTool in @($sdkManager, $avdManager)) {
    if (-not (Test-Path $requiredTool)) {
        Stop-WithError "缺少 Android command-line tools：$requiredTool。无需安装 Android Studio，但需先安装 Google command-line tools。"
    }
}

$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
& flutter config --android-sdk $AndroidSdk | Out-Host

$gradleSdkPath = $AndroidSdk.Replace('\', '\\')
$flutterSdkPath = (Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)).Replace('\', '\\')
$localPropertiesPath = Join-Path $projectRoot 'android\local.properties'
$localProperties = @(
    "flutter.sdk=$flutterSdkPath"
    "sdk.dir=$gradleSdkPath"
) -join [Environment]::NewLine
Set-Content -LiteralPath $localPropertiesPath -Value $localProperties -Encoding utf8

$systemImage = "system-images;android-$ApiLevel;google_apis_playstore;x86_64"
$requiredPackages = @(
    'platform-tools'
    'emulator'
    "platforms;android-$ApiLevel"
    $systemImage
)
$installedPackages = (& $sdkManager --list_installed 2>&1 | Out-String)
$missingPackages = @($requiredPackages | Where-Object { $installedPackages -notmatch [regex]::Escape($_) })
if ($missingPackages.Count -gt 0) {
    Write-Host "正在安装缺少的 Android 组件：$($missingPackages -join ', ')"
    & $sdkManager @missingPackages
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError 'Android SDK 组件安装失败。'
    }
}

foreach ($requiredTool in @($adb, $emulator)) {
    if (-not (Test-Path $requiredTool)) {
        Stop-WithError "Android 组件安装后仍找不到：$requiredTool"
    }
}

$avdList = (& $avdManager list avd 2>&1 | Out-String)
if ($avdList -notmatch "(?m)^\s*Name:\s*$([regex]::Escape($AvdName))\s*$") {
    Write-Host "正在创建模拟器 $AvdName ..."
    'no' | & $avdManager create avd --force --name $AvdName --package $systemImage --device $DeviceProfile
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError "创建模拟器 $AvdName 失败。"
    }
}

function Get-RunningEmulatorSerial {
    $match = & $adb devices | Select-String '^(emulator-\d+)\s+device$' | Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value }
    return ''
}

& $adb start-server | Out-Null
$emulatorSerial = Get-RunningEmulatorSerial
if ([string]::IsNullOrWhiteSpace($emulatorSerial)) {
    Write-Host "正在启动模拟器 $AvdName ..."
    $emulatorArguments = @('-avd', $AvdName, '-no-snapshot-save')
    if ($ColdBoot) {
        $emulatorArguments += '-no-snapshot-load'
    }
    Start-Process -FilePath $emulator -ArgumentList $emulatorArguments | Out-Null

    $deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
    $bootCompleted = ''
    do {
        Start-Sleep -Seconds 2
        $emulatorSerial = Get-RunningEmulatorSerial
        if (-not [string]::IsNullOrWhiteSpace($emulatorSerial)) {
            $bootCompleted = (& $adb -s $emulatorSerial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        }
    } while (($bootCompleted -ne '1') -and ((Get-Date) -lt $deadline))

    if ($bootCompleted -ne '1') {
        Stop-WithError "模拟器在 $BootTimeoutSeconds 秒内未完成启动。"
    }
}

Write-Host "Android 模拟器已就绪：$emulatorSerial"
if (-not $NoRun) {
    Set-Location $projectRoot
    & flutter run -d $emulatorSerial
    exit $LASTEXITCODE
}
