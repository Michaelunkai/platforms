$todoistPath = Get-ChildItem 'C:\Program Files\WindowsApps' -Filter '*Todoist*' -Directory | Select-Object -First 1 -ExpandProperty FullName
$todoistExe = Join-Path $todoistPath 'app\Todoist.exe'

Write-Host "Testing: $todoistExe" -ForegroundColor Yellow

try {
    $p = Start-Process $todoistExe -PassThru -ErrorAction Stop
    Start-Sleep -Seconds 2
    if ($p -and !$p.HasExited) {
        Write-Host 'SUCCESS - Todoist launched directly!' -ForegroundColor Green
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "FAILED - Still blocked: $($_.Exception.Message)" -ForegroundColor Red
}
