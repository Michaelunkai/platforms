# Find correct AppUserModelIds for Todoist and Slack

Write-Host "Finding AppUserModelIds..." -ForegroundColor Cyan

# Get all installed apps
$apps = Get-AppxPackage | Where-Object { $_.Name -like "*Todoist*" -or $_.Name -like "*Slack*" }

foreach ($app in $apps) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "App Name: $($app.Name)" -ForegroundColor Green
    Write-Host "Package Family Name: $($app.PackageFamilyName)" -ForegroundColor Green
    Write-Host "Install Location: $($app.InstallLocation)" -ForegroundColor Gray

    # Find the AppUserModelId
    $manifestPath = Join-Path $app.InstallLocation "AppxManifest.xml"
    if (Test-Path $manifestPath) {
        [xml]$manifest = Get-Content $manifestPath
        $apps = $manifest.Package.Applications.Application
        foreach ($application in $apps) {
            $appId = $application.Id
            $aumid = "$($app.PackageFamilyName)!$appId"
            Write-Host "AppUserModelId: $aumid" -ForegroundColor Cyan
        }
    }
}
