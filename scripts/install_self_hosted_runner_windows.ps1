param(
    [string]$Repo = "BrainEno/book-management-system",
    [string]$InstallDir = "C:\actions-runner-bookstore",
    [string]$RunnerName = "$env:COMPUTERNAME-bookstore-win",
    [int]$PreferredProxyPort = 10808
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run PowerShell as Administrator and run this script again."
    }
}

function Ensure-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$WingetId
    )

    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed and winget is unavailable. Install $Name manually, then rerun this script."
    }

    Write-Host "Installing $Name..." -ForegroundColor Cyan
    winget install --id $WingetId -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $Name with winget."
    }

    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was installed but is not visible in this PowerShell session. Reopen PowerShell as Administrator and rerun this script."
    }
}

function Test-HttpProxy {
    param([Parameter(Mandatory = $true)][string]$ProxyUrl)

    & curl.exe --silent --show-error --fail --head --max-time 5 --proxy $ProxyUrl https://github.com/ *> $null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-GitHubProxy {
    param([int]$PreferredPort)

    $ports = @($PreferredPort, 10808, 10809, 7890, 7897, 1080) | Select-Object -Unique
    foreach ($port in $ports) {
        $candidate = "http://127.0.0.1:$port"
        Write-Host "Checking local proxy $candidate ..." -ForegroundColor DarkGray
        if (Test-HttpProxy -ProxyUrl $candidate) {
            return $candidate
        }
    }

    Write-Host "No local HTTP proxy detected. Testing direct GitHub access..." -ForegroundColor DarkGray
    & curl.exe --silent --show-error --fail --head --max-time 8 https://github.com/ *> $null
    if ($LASTEXITCODE -eq 0) {
        return $null
    }

    throw "GitHub is unreachable directly and no working local HTTP proxy was found. Checked ports: $($ports -join ', ')."
}

function Set-ProcessProxy {
    param([AllowNull()][string]$ProxyUrl)

    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
        return
    }

    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:http_proxy = $ProxyUrl
    $env:https_proxy = $ProxyUrl
    Write-Host "Using GitHub proxy: $ProxyUrl" -ForegroundColor Green
}

function Write-RunnerProxyEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$RunnerDir,
        [AllowNull()][string]$ProxyUrl
    )

    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
        return
    }

    $envPath = Join-Path $RunnerDir ".env"
    @(
        "http_proxy=$ProxyUrl"
        "https_proxy=$ProxyUrl"
        "no_proxy=localhost,127.0.0.1"
    ) | Set-Content -Path $envPath -Encoding utf8

    Write-Host "Persisted runner proxy settings to $envPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Book Management System - GitHub self-hosted runner installer" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host "Install dir: $InstallDir"
Write-Host "Runner name: $RunnerName"
Write-Host "Preferred proxy port: $PreferredProxyPort"
Write-Host ""

Assert-Administrator
Ensure-Command -Name "git" -WingetId "Git.Git"
Ensure-Command -Name "gh" -WingetId "GitHub.cli"

$proxyUrl = Resolve-GitHubProxy -PreferredPort $PreferredProxyPort
Set-ProcessProxy -ProxyUrl $proxyUrl

& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub authentication is required. A browser login will open once." -ForegroundColor Yellow
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub authentication failed."
    }
}

if (Test-Path (Join-Path $InstallDir ".runner")) {
    Write-Host "Runner is already configured in $InstallDir." -ForegroundColor Green
    Write-RunnerProxyEnvironment -RunnerDir $InstallDir -ProxyUrl $proxyUrl

    $existingServices = Get-Service "actions.runner.*" -ErrorAction SilentlyContinue
    if ($existingServices) {
        Write-Host "Restarting runner service so proxy settings take effect..." -ForegroundColor Cyan
        $existingServices | Restart-Service -Force
        Start-Sleep -Seconds 2
        Get-Service "actions.runner.*" -ErrorAction SilentlyContinue | Format-Table Status, Name, DisplayName
    }

    Write-Host "Existing runner proxy configuration refreshed successfully." -ForegroundColor Green
    exit 0
}

if ((Test-Path $InstallDir) -and ((Get-ChildItem $InstallDir -Force -ErrorAction SilentlyContinue).Count -gt 0)) {
    throw "$InstallDir exists and is not empty, but no configured runner was found. Inspect or remove that directory before retrying."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-RunnerProxyEnvironment -RunnerDir $InstallDir -ProxyUrl $proxyUrl

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($architecture) {
    "X64"   { $runnerArch = "x64" }
    "Arm64" { $runnerArch = "arm64" }
    default { throw "Unsupported Windows architecture: $architecture" }
}

Write-Host "Resolving latest GitHub Actions runner release..." -ForegroundColor Cyan
$release = (& gh api repos/actions/runner/releases/latest | ConvertFrom-Json)
$version = $release.tag_name.TrimStart("v")
$assetName = "actions-runner-win-$runnerArch-$version.zip"
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1

if (-not $asset) {
    throw "Runner asset not found: $assetName"
}

$archivePath = Join-Path $env:TEMP $assetName
Write-Host "Downloading $assetName..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath
Expand-Archive -Path $archivePath -DestinationPath $InstallDir -Force
Remove-Item $archivePath -Force

Write-Host "Requesting a short-lived repository registration token..." -ForegroundColor Cyan
$registrationToken = & gh api --method POST "repos/$Repo/actions/runners/registration-token" --jq '.token'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($registrationToken)) {
    throw "Could not obtain a runner registration token. The signed-in GitHub account must have Admin access to $Repo."
}

Push-Location $InstallDir
try {
    & .\config.cmd `
        --unattended `
        --replace `
        --url "https://github.com/$Repo" `
        --token $registrationToken `
        --name $RunnerName `
        --labels "bookstore,flutter,bookstore-windows" `
        --work "_work" `
        --runasservice

    if ($LASTEXITCODE -ne 0) {
        throw "GitHub Actions runner configuration failed."
    }
} finally {
    Pop-Location
}

Start-Sleep -Seconds 2
$runnerServices = Get-Service "actions.runner.*" -ErrorAction SilentlyContinue
if (-not $runnerServices) {
    throw "Runner configuration completed, but no GitHub Actions Windows service was found."
}

Write-Host ""
Write-Host "Windows self-hosted runner installed successfully." -ForegroundColor Green
$runnerServices | Format-Table Status, Name, DisplayName
Write-Host ""
Write-Host "Expected custom labels: bookstore, flutter, bookstore-windows"
Write-Host "Runner page: https://github.com/$Repo/settings/actions/runners"
Write-Host "The Windows service will start automatically with Windows."
