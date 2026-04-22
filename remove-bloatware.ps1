# Remove bloatware UWP apps for kiosk setup
# BC Silly - Windows 11 Home

$apps = @(
    "Microsoft.BingSearch",
    "Microsoft.Copilot",
    "Microsoft.Edge.GameAssist",
    "Microsoft.GetHelp",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.OneDriveSync",
    "Microsoft.OutlookForWindows",
    "Microsoft.Paint",
    "Microsoft.People",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.Todos",
    "Microsoft.Windows.DevHome",
    "Microsoft.WindowsAlarms",
    "microsoft.windowscommunicationsapps",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameCallableUI",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone",
    "MicrosoftCorporationII.MicrosoftFamily",
    "MicrosoftTeams",
    "MSTeams",
    "B9ECED6F.ASUSPCAssistant",
    "MicrosoftWindows.Client.WebExperience",
    "MicrosoftWindows.CrossDevice"
)

$removed = 0
$skipped = 0

foreach ($app in $apps) {
    $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
    if ($pkg) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
            Write-Output "REMOVED: $app"
            $removed++
        } catch {
            Write-Output "FAILED: $app - $($_.Exception.Message)"
        }
    } else {
        Write-Output "SKIP: $app (not found)"
        $skipped++
    }
}

Write-Output ""
Write-Output "Done. Removed: $removed, Skipped: $skipped"
