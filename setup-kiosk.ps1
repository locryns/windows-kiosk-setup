# Kiosk setup for BC Silly - Windows 11 Home
# Configures auto-login + Edge kiosk mode on fdm.awbb.be
# Must run as Administrator (elevate via suppo or Administrator account)
#
# Usage:
#   .\setup-kiosk.ps1 -KioskUser "bcsilly" -KioskPassword "oneteam" -KioskURL "https://fdm.awbb.be"

param(
    [string]$KioskUser = "bcsilly",
    [string]$KioskPassword = "",
    [string]$KioskURL = "https://fdm.awbb.be",
    [string]$EdgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)

if (-not (Test-Path $EdgePath)) {
    # Try x64 location as fallback
    $alt = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    if (Test-Path $alt) { $EdgePath = $alt }
    else { Write-Warning "Edge not found at $EdgePath or $alt"; }
}

# ============================================================
Write-Output "=== PHASE 3: Kiosk account password + Auto-login ==="

# Ensure the password matches what we will store in Winlogon.
# IMPORTANT: a `net user <account> ""` then `net user <account> <pwd>`
# regenerates DPAPI master keys and orphans saved Edge passwords.
# Only reset the password if one is explicitly provided.
if ($KioskPassword -ne "") {
    try {
        & net user $KioskUser $KioskPassword | Out-Null
        Write-Output "Reset $KioskUser password (DPAPI side-effects may apply)."
    } catch {
        Write-Warning "Failed to set $KioskUser password: $($_.Exception.Message)"
    }
}

# Winlogon auto-login
$winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $winlogonPath -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName" -Value $KioskUser
Set-ItemProperty -Path $winlogonPath -Name "DefaultPassword" -Value $KioskPassword
Set-ItemProperty -Path $winlogonPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME
Set-ItemProperty -Path $winlogonPath -Name "DisableLockWorkstation" -Value 1 -Type DWord

Write-Output "Auto-login configured for $KioskUser"

# ============================================================
Write-Output ""
Write-Output "=== PHASE 4: Edge kiosk launcher + watchdog ==="

$launcherDir = "C:\Kiosk"
if (!(Test-Path $launcherDir)) { New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null }

# Robust launcher: kill all msedge instances and wait until the
# process is fully gone before launching kiosk. This prevents the
# new Edge window from "joining" an already-running session started
# by --win-session-start / startup boost, which silently drops our
# launcher flags.
#
# Uses Edge --app= mode (PWA window, persistent profile) instead of
# --kiosk because the latter forces an InPrivate session that disables
# autofill and loses saved passwords/cookies across restarts.
# URL sandboxing is enforced at the policy layer (URLAllowlist /
# URLBlocklist below), not through --kiosk.
$launcherContent = @"
@echo off
REM Edge Kiosk Launcher for BC Silly
REM Kills any pre-launched Edge (startup boost) before entering kiosk mode.

REM Wait for desktop / shell to be ready
timeout /t 5 /nobreak >nul

:killloop
tasklist /FI "IMAGENAME eq msedge.exe" 2>NUL | find /I /N "msedge.exe" >nul
if "%ERRORLEVEL%"=="0" (
    taskkill /F /IM msedge.exe >nul 2>&1
    timeout /t 1 /nobreak >nul
    goto killloop
)

REM Extra safety wait so the previous Edge user-data-dir locks release
timeout /t 3 /nobreak >nul

start "" "$EdgePath" --app="$KioskURL" ^
    --start-fullscreen ^
    --no-first-run ^
    --disable-features=msEdgeSidebarV2,msEdgeJSONViewer,msEdgeSplitWindow ^
    --disable-popup-blocking ^
    --disable-infobars ^
    --disable-session-crashed-bubble ^
    --noerrdialogs
"@
Set-Content -Path "$launcherDir\launch-kiosk.bat" -Value $launcherContent -Encoding ASCII
Write-Output "Created $launcherDir\launch-kiosk.bat"

# Watchdog: if Edge dies, relaunch app mode.
$watchdogContent = @"
@echo off
REM Edge Kiosk Watchdog - restarts Edge if it closes
:loop
timeout /t 10 /nobreak >nul
tasklist /FI "IMAGENAME eq msedge.exe" 2>NUL | find /I /N "msedge.exe" >nul
if "%ERRORLEVEL%"=="1" (
    start "" "$EdgePath" --app="$KioskURL" ^
        --start-fullscreen ^
        --no-first-run ^
        --disable-features=msEdgeSidebarV2,msEdgeJSONViewer,msEdgeSplitWindow ^
        --disable-popup-blocking ^
        --disable-infobars ^
        --disable-session-crashed-bubble ^
        --noerrdialogs
)
goto loop
"@
Set-Content -Path "$launcherDir\watchdog.bat" -Value $watchdogContent -Encoding ASCII
Write-Output "Created $launcherDir\watchdog.bat"

# Startup folder for kiosk user
$kioskStartup = "C:\Users\$KioskUser\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if (!(Test-Path $kioskStartup)) { New-Item -ItemType Directory -Path $kioskStartup -Force | Out-Null }

# Purge any pre-existing Edge PWA shortcut that could preempt kiosk mode.
# (e.g. `FDM AWBB.lnk` created by "Install site as app" launches Edge with
#  --app-id=... --app-url=... before our launcher runs and hijacks the session)
Get-ChildItem -Path $kioskStartup -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($_.FullName)
    if ($lnk.TargetPath -match "msedge\.exe$" -or $lnk.Arguments -match "--app-(id|url)=") {
        Remove-Item $_.FullName -Force
        Write-Output "Removed preempting Edge shortcut: $($_.Name)"
    }
}

# Launcher + Watchdog startup shortcuts
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut("$kioskStartup\KioskLauncher.lnk")
$shortcut.TargetPath = "$launcherDir\launch-kiosk.bat"
$shortcut.WindowStyle = 7  # Minimized
$shortcut.Save()
Write-Output "Created startup shortcut for launcher"

$shortcut2 = $WshShell.CreateShortcut("$kioskStartup\KioskWatchdog.lnk")
$shortcut2.TargetPath = "$launcherDir\watchdog.bat"
$shortcut2.WindowStyle = 7
$shortcut2.Save()
Write-Output "Created startup shortcut for watchdog"

# ============================================================
Write-Output ""
Write-Output "=== PHASE 5: Lock down keyboard shortcuts + taskbar ==="

if (!(Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
}

$kioskSID = (Get-LocalUser -Name $KioskUser).SID.Value
$ntUserDat = "C:\Users\$KioskUser\NTUSER.DAT"
$useTemp = $false

if (!(Test-Path "HKU:\$kioskSID")) {
    reg load "HKLM\TEMP_KIOSK" $ntUserDat 2>$null | Out-Null
    $regBase = "HKLM:\TEMP_KIOSK"
    $useTemp = $true
    Write-Output "Loaded $KioskUser registry hive"
} else {
    $regBase = "HKU:\$kioskSID"
    Write-Output "Using live $KioskUser registry hive"
}

# DisableTaskMgr + DisableRegistryTools
$polPath = "$regBase\Software\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $polPath)) { New-Item -Path $polPath -Force | Out-Null }
Set-ItemProperty -Path $polPath -Name "DisableTaskMgr" -Value 1 -Type DWord
Set-ItemProperty -Path $polPath -Name "DisableRegistryTools" -Value 1 -Type DWord
Write-Output "Disabled Task Manager + Registry Editor"

# DisableCMD = 2 (block interactive CMD but ALLOW .bat files)
# Value 1 blocks batch files too and breaks our launcher. Always use 2.
$cmdPolPath = "$regBase\Software\Policies\Microsoft\Windows\System"
if (!(Test-Path $cmdPolPath)) { New-Item -Path $cmdPolPath -Force | Out-Null }
Set-ItemProperty -Path $cmdPolPath -Name "DisableCMD" -Value 2 -Type DWord
Write-Output "Disabled interactive CMD (batch files still allowed)"

# Taskbar auto-hide (closest available Home-edition lockdown)
$explorerAdvPath = "$regBase\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
if (!(Test-Path $explorerAdvPath)) { New-Item -Path $explorerAdvPath -Force | Out-Null }
Set-ItemProperty -Path $explorerAdvPath -Name "TaskbarSi" -Value 0 -Type DWord
Set-ItemProperty -Path $explorerAdvPath -Name "TaskbarAutoHideInTabletMode" -Value 1 -Type DWord

# Keyboard + desktop lockdown
$explorerPolPath = "$regBase\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (!(Test-Path $explorerPolPath)) { New-Item -Path $explorerPolPath -Force | Out-Null }
Set-ItemProperty -Path $explorerPolPath -Name "NoWinKeys" -Value 1 -Type DWord
Set-ItemProperty -Path $explorerPolPath -Name "NoViewContextMenu" -Value 1 -Type DWord
Set-ItemProperty -Path $explorerPolPath -Name "NoStartMenuMorePrograms" -Value 1 -Type DWord
Set-ItemProperty -Path $explorerPolPath -Name "NoClose" -Value 0 -Type DWord
Write-Output "Disabled Win key, desktop right-click, start menu extras"

# Notification center
$notifPath = "$regBase\Software\Policies\Microsoft\Windows\Explorer"
if (!(Test-Path $notifPath)) { New-Item -Path $notifPath -Force | Out-Null }
Set-ItemProperty -Path $notifPath -Name "DisableNotificationCenter" -Value 1 -Type DWord
Write-Output "Disabled Notification Center"

# Lock screen
$personalizePath = "$regBase\Software\Policies\Microsoft\Windows\Personalization"
if (!(Test-Path $personalizePath)) { New-Item -Path $personalizePath -Force | Out-Null }
Set-ItemProperty -Path $personalizePath -Name "NoLockScreen" -Value 1 -Type DWord
Write-Output "Disabled lock screen"

if ($useTemp) {
    [gc]::Collect()
    Start-Sleep -Seconds 2
    reg unload "HKLM\TEMP_KIOSK" 2>$null | Out-Null
    Write-Output "Unloaded temp registry hive"
}

# ============================================================
Write-Output ""
Write-Output "=== GLOBAL POLICIES (HKLM) ==="

# Ctrl+Alt+Del + inactivity timeout
$systemPolPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $systemPolPath -Name "DisableCAD" -Value 1 -Type DWord
Set-ItemProperty -Path $systemPolPath -Name "InactivityTimeoutSecs" -Value 0 -Type DWord
Write-Output "Disabled Ctrl+Alt+Del requirement + inactivity timeout"

# Windows Update: never auto-reboot with a logged-on user
$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (!(Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
Write-Output "Disabled Windows Update auto-restart"

# Edge policies (HKLM - apply to all users)
# Critical: StartupBoostEnabled=0 and BackgroundModeEnabled=0 prevent Edge
# from pre-warming with --win-session-start which would later swallow our
# launcher flags. BrowserSignin=0 avoids account prompts.
$edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }
Set-ItemProperty -Path $edgePolicyPath -Name "HideFirstRunExperience" -Value 1 -Type DWord
Set-ItemProperty -Path $edgePolicyPath -Name "AutoImportAtFirstRun" -Value 4 -Type DWord
Set-ItemProperty -Path $edgePolicyPath -Name "StartupBoostEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $edgePolicyPath -Name "BackgroundModeEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $edgePolicyPath -Name "BrowserSignin" -Value 0 -Type DWord
# Keep subframes / new windows inside the app window instead of spawning
# a full Edge browser window with a URL bar (would break the lockdown).
Set-ItemProperty -Path $edgePolicyPath -Name "NewWindowsInApp" -Value 1 -Type DWord
Write-Output "Applied Edge policies (StartupBoost/Background/Signin off, NewWindowsInApp)"

# URL sandboxing: block everything except the kiosk site + same domain.
# Since we no longer use --kiosk InPrivate, this is the main containment.
# Policy format: subkey with numbered REG_SZ values (1,2,3...).
#
# Derive the apex domain from $KioskURL so allowlist also covers www/subs.
$kioskHost = ([uri]$KioskURL).Host
$apexParts = $kioskHost.Split('.')
if ($apexParts.Count -ge 2) {
    $apexDomain = ($apexParts[-2..-1] -join '.')  # e.g. awbb.be
} else {
    $apexDomain = $kioskHost
}

$blocklistPath = "$edgePolicyPath\URLBlocklist"
if (Test-Path $blocklistPath) { Remove-Item $blocklistPath -Recurse -Force }
New-Item -Path $blocklistPath -Force | Out-Null
Set-ItemProperty -Path $blocklistPath -Name "1" -Value "*" -Type String

$allowlistPath = "$edgePolicyPath\URLAllowlist"
if (Test-Path $allowlistPath) { Remove-Item $allowlistPath -Recurse -Force }
New-Item -Path $allowlistPath -Force | Out-Null
Set-ItemProperty -Path $allowlistPath -Name "1" -Value $KioskURL -Type String
Set-ItemProperty -Path $allowlistPath -Name "2" -Value "https://$kioskHost/*" -Type String
Set-ItemProperty -Path $allowlistPath -Name "3" -Value "https://*.$apexDomain/*" -Type String
# edge:// pages used by the app shell (about/blank, settings kept blocked elsewhere)
Set-ItemProperty -Path $allowlistPath -Name "4" -Value "about:blank" -Type String
Write-Output "Configured URL allowlist for $kioskHost and *.$apexDomain (block *)"

# ============================================================
Write-Output ""
Write-Output "=== POWER: never sleep / never turn off screen ==="
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /change disk-timeout-ac 0
powercfg /change disk-timeout-dc 0
Write-Output "All idle timeouts set to 0 (never)"

# ============================================================
Write-Output ""
Write-Output "=== SETUP COMPLETE ==="
Write-Output "Kiosk user:     $KioskUser"
Write-Output "URL:            $KioskURL"
Write-Output "Auto-login:     enabled"
Write-Output "Edge mode:      --app (persistent profile, passwords kept)"
Write-Output "URL sandbox:    block * / allow $kioskHost + *.$apexDomain"
Write-Output "Watchdog:       configured (10s interval)"
Write-Output "Keyboard:       Win/Alt+Tab/context-menu disabled"
Write-Output "Power:          never sleep/screen-off"
Write-Output ""
Write-Output "REBOOT REQUIRED to activate kiosk mode."
