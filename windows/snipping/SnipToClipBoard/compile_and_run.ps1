# Kill any running instances
Get-Process FullScreenSnip -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# Compile with proper references
$csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
$source = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip_Fixed.cs"
$output = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe"

Write-Host "Compiling enhanced version..." -ForegroundColor Yellow

# Remove old exe
if (Test-Path $output) { Remove-Item $output -Force }

# Compile with all required references
& $csc /target:winexe /out:$output /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.dll /r:System.Core.dll $source 2>&1

if (Test-Path $output) {
    Write-Host "✅ Compiled successfully: $((Get-Item $output).Length) bytes" -ForegroundColor Green
    
    # Start the application
    Write-Host "Starting FullScreenSnip..." -ForegroundColor Cyan
    Start-Process $output
    
    # Wait and verify
    Start-Sleep -Seconds 3
    $proc = Get-Process FullScreenSnip -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "✅ FullScreenSnip is running! Check your system tray for the blue camera icon." -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to start. Checking for errors..." -ForegroundColor Red
    }
} else {
    Write-Host "❌ Compilation failed!" -ForegroundColor Red
}