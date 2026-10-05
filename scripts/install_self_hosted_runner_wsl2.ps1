param(
    [string]$Repo = "BrainEno/book-management-system",
    [string]$Distro = "",
    [int]$PreferredProxyPort = 10808,
    [string]$StartupTaskName = "Bookstore WSL2 Runner"
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run PowerShell as Administrator and run this script again."
    }
}

function Get-WindowsBuildNumber {
    try {
        return [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber
    }
    catch {
        return [int][Environment]::OSVersion.Version.Build
    }
}

function Update-WslIfPossible {
    Write-Host "Updating WSL before configuring networking..." -ForegroundColor Cyan
    & wsl.exe --update *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "'wsl --update' did not complete successfully. Continuing with the installed WSL version."
    }
}

function Set-Wsl2ConfigValues {
    param([System.Collections.IDictionary]$Values)

    $configPath = Join-Path $env:USERPROFILE ".wslconfig"
    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path $configPath) {
        foreach ($line in (Get-Content -Path $configPath -ErrorAction Stop)) {
            [void]$lines.Add([string]$line)
        }
    }

    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[wsl2\]\s*$') {
            $sectionIndex = $i
            break
        }
    }

    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            [void]$lines.Add("")
        }
        [void]$lines.Add("[wsl2]")
        $sectionIndex = $lines.Count - 1
    }

    foreach ($key in $Values.Keys) {
        $sectionEnd = $lines.Count
        for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[[^\]]+\]\s*$') {
                $sectionEnd = $i
                break
            }
        }

        $keyIndex = -1
        $escapedKey = [regex]::Escape([string]$key)
        for ($i = $sectionIndex + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -match "^\s*$escapedKey\s*=") {
                $keyIndex = $i
                break
            }
        }

        $newLine = "${key}=$($Values[$key])"
        if ($keyIndex -ge 0) {
            $lines[$keyIndex] = $newLine
        }
        else {
            $lines.Insert($sectionEnd, $newLine)
        }
    }

    $newContent = [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine
    $oldContent = ""
    if (Test-Path $configPath) {
        $oldContent = [System.IO.File]::ReadAllText($configPath)
    }

    if ($oldContent -eq $newContent) {
        return $false
    }

    if (Test-Path $configPath) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$configPath.bookstore-$stamp.bak"
        Copy-Item -Path $configPath -Destination $backupPath -Force
        Write-Host "Backed up existing WSL config to $backupPath" -ForegroundColor DarkGray
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $newContent, $utf8NoBom)
    return $true
}

function Configure-WslNetworking {
    $build = Get-WindowsBuildNumber
    Write-Host "Windows build: $build" -ForegroundColor DarkGray

    if ($build -ge 22621) {
        Update-WslIfPossible

        $values = [ordered]@{
            networkingMode = "mirrored"
            dnsTunneling   = "true"
            autoProxy      = "true"
        }

        $changed = Set-Wsl2ConfigValues -Values $values
        if ($changed) {
            Write-Host "Configured WSL2 mirrored networking, DNS tunneling, and Windows proxy mirroring." -ForegroundColor Green
        }
        else {
            Write-Host "WSL2 mirrored networking and auto-proxy are already configured." -ForegroundColor Green
        }

        # .wslconfig networking changes only take effect after every WSL VM is stopped.
        & wsl.exe --shutdown *> $null
        Start-Sleep -Seconds 2
        return "mirrored"
    }

    Write-Warning "Windows build $build does not support WSL mirrored networking. The Linux bootstrap will fall back to NAT mode and automatically probe the Windows host/gateway IP for proxy port $PreferredProxyPort. If your proxy only listens on 127.0.0.1, enable 'Allow LAN' (or equivalent) in the proxy application."
    return "nat"
}

function Get-WslDistributions {
    $items = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        $items |
            ForEach-Object { $_.Replace([string][char]0, "").Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Resolve-WslDistribution {
    param([string]$Requested)

    $distros = @(Get-WslDistributions)
    if ($distros.Count -eq 0) {
        Write-Host "No WSL distribution is installed. Requesting Ubuntu installation..." -ForegroundColor Yellow
        & wsl.exe --install -d Ubuntu
        if ($LASTEXITCODE -ne 0) {
            throw "Ubuntu installation failed. Run 'wsl --install -d Ubuntu' manually, restart Windows if requested, launch Ubuntu once, then rerun this script."
        }

        throw "Ubuntu installation was requested. Complete any Windows restart and the one-time Ubuntu username/password screen, then rerun this script. Everything after that is automated."
    }

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if ($distros -contains $Requested) {
            return $Requested
        }
        throw "WSL distribution '$Requested' was not found. Installed distributions: $($distros -join ', ')"
    }

    $ubuntu = $distros | Where-Object { $_ -match '^Ubuntu' } | Select-Object -First 1
    if ($ubuntu) {
        return $ubuntu
    }

    return $distros[0]
}

function Ensure-Wsl2 {
    param([string]$Distribution)

    & wsl.exe -d $Distribution -- sh -lc "grep -qi 'microsoft-standard-WSL2' /proc/sys/kernel/osrelease"
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Host "Converting '$Distribution' to WSL2..." -ForegroundColor Cyan
    & wsl.exe --set-version $Distribution 2
    if ($LASTEXITCODE -ne 0) {
        throw "Could not convert '$Distribution' to WSL2."
    }
}

function Enable-Systemd {
    param([string]$Distribution)

    Write-Host "Ensuring systemd is enabled inside $Distribution..." -ForegroundColor Cyan

    # Avoid nested shell quoting across Windows PowerShell and wsl.exe.
    # Write the minimal systemd config through stdin instead.
    $wslConfText = "[boot]`nsystemd=true`n"
    $wslConfText | & wsl.exe -d $Distribution -u root -- tee /etc/wsl.conf | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enable systemd in /etc/wsl.conf."
    }

    & wsl.exe --shutdown *> $null
    Start-Sleep -Seconds 2
    & wsl.exe -d $Distribution --exec /bin/true *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "WSL failed to restart after enabling systemd."
    }

    Start-Sleep -Seconds 2
    & wsl.exe -d $Distribution -- sh -lc 'ps -p 1 -o comm= | grep -qx systemd'
    if ($LASTEXITCODE -ne 0) {
        throw "systemd is still not active in '$Distribution'. Check /etc/wsl.conf and rerun this script."
    }
}

function Convert-WindowsPathToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Unsupported Windows path for WSL conversion: $fullPath"
    }

    $drive = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2] -replace '\\', '/'
    return "/mnt/$drive/$relative"
}

function Invoke-LinuxBootstrap {
    param(
        [string]$Distribution,
        [string]$Repository,
        [int]$ProxyPort,
        [string]$NetworkMode
    )

    $linuxInstallerWindowsPath = Join-Path $PSScriptRoot "install_self_hosted_runner_wsl2.sh"
    if (-not (Test-Path $linuxInstallerWindowsPath)) {
        throw "Missing companion installer: $linuxInstallerWindowsPath"
    }

    # Windows Git checkouts often use CRLF. Bash treats the trailing CR in
    # `set -euo pipefail` as part of the option name, so normalize a temporary
    # copy to LF before invoking it in WSL. This keeps the bootstrap robust even
    # before .gitattributes has had a chance to re-normalize the local checkout.
    $normalizedInstallerWindowsPath = Join-Path $env:TEMP "bookstore-wsl2-bootstrap.sh"
    $installerText = [System.IO.File]::ReadAllText($linuxInstallerWindowsPath)
    $installerText = $installerText.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($normalizedInstallerWindowsPath, $installerText, $utf8NoBom)

    $linuxInstallerPath = Convert-WindowsPathToWslPath -WindowsPath $normalizedInstallerWindowsPath
    Write-Host "Linux bootstrap path: $linuxInstallerPath" -ForegroundColor DarkGray

    try {
        Write-Host "Running Linux bootstrap inside $Distribution..." -ForegroundColor Cyan
        & wsl.exe -d $Distribution -- env `
            "REPO=$Repository" `
            "PREFERRED_PROXY_PORT=$ProxyPort" `
            "WSL_NETWORK_MODE_HINT=$NetworkMode" `
            bash $linuxInstallerPath

        if ($LASTEXITCODE -ne 0) {
            throw "WSL2 Linux bootstrap failed."
        }
    }
    finally {
        Remove-Item -Path $normalizedInstallerWindowsPath -Force -ErrorAction SilentlyContinue
    }
}

function Register-WslStartupTask {
    param(
        [string]$Distribution,
        [string]$TaskName
    )

    $wslPath = Join-Path $env:SystemRoot "System32\wsl.exe"
    $taskRun = "`"$wslPath`" -d `"$Distribution`" --exec /bin/true"

    Write-Host "Creating Windows logon task '$TaskName' so WSL/systemd starts after sign-in..." -ForegroundColor Cyan
    & schtasks.exe /Create /SC ONLOGON /TN $TaskName /TR $taskRun /F | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the WSL startup scheduled task."
    }
}

Write-Host ""
Write-Host "Book Management System - WSL2 self-hosted runner bootstrap" -ForegroundColor Cyan
Write-Host "Repository: $Repo"
Write-Host "Preferred Windows proxy port: $PreferredProxyPort"
Write-Host ""

Assert-Administrator

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe is unavailable. Enable Windows Subsystem for Linux first."
}

$networkMode = Configure-WslNetworking
$resolvedDistro = Resolve-WslDistribution -Requested $Distro
Write-Host "Using WSL distribution: $resolvedDistro" -ForegroundColor Green
Write-Host "WSL networking strategy: $networkMode" -ForegroundColor Green

Ensure-Wsl2 -Distribution $resolvedDistro
Enable-Systemd -Distribution $resolvedDistro
Invoke-LinuxBootstrap -Distribution $resolvedDistro -Repository $Repo -ProxyPort $PreferredProxyPort -NetworkMode $networkMode
Register-WslStartupTask -Distribution $resolvedDistro -TaskName $StartupTaskName

Write-Host ""
Write-Host "WSL2 self-hosted runner bootstrap completed." -ForegroundColor Green
Write-Host "Distribution: $resolvedDistro"
Write-Host "Networking strategy: $networkMode"
Write-Host "Expected custom labels: bookstore, flutter, bookstore-wsl"
Write-Host "Runner page: https://github.com/$Repo/settings/actions/runners"
Write-Host "At each Windows sign-in, the scheduled task boots WSL so the systemd runner service can come online."
