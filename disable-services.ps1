# Disable unnecessary services for kiosk setup
# BC Silly - Windows 11 Home
# Must run as Administrator

$services = @(
    # Telemetry & diagnostics
    "DiagTrack",           # Connected User Experiences and Telemetry
    "dmwappushservice",    # WAP Push Message Routing

    # Performance hogs
    "SysMain",             # Superfetch - heavy on disk/RAM
    "WSearch",             # Windows Search indexer

    # Print (not needed for kiosk)
    "Spooler",             # Print Spooler

    # Phone/mobile
    "PhoneSvc",            # Phone Service
    
    # Location
    "lfsvc",               # Geolocation Service
    "SensorService",       # Sensor Service

    # ASUS bloatware services
    "AsusAppService",
    "ASUSOptimization",
    "ASUSSoftwareManager",
    "ASUSSwitch",
    "ASUSSystemAnalysis",
    "ASUSSystemDiagnosis",
    "ImControllerService",

    # Thunderbolt (not used)
    "TbtP2pShortcutService",

    # Xbox (apps already removed)
    # These may not exist as standalone services

    # DTS Audio (not needed for web kiosk)
    "DtsApo4Service"
)

$disabled = 0
$failed = 0

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        try {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Write-Output "DISABLED: $svc ($($service.DisplayName))"
            $disabled++
        } catch {
            Write-Output "FAILED: $svc - $($_.Exception.Message)"
            $failed++
        }
    } else {
        Write-Output "SKIP: $svc (not found)"
    }
}

Write-Output ""
Write-Output "Done. Disabled: $disabled, Failed: $failed"
