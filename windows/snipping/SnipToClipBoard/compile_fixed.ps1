# Compile FullScreenSnip_Fixed.cs
$csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
$source = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip_Fixed.cs"
$output = "F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe"

# Kill any running instance
Get-Process FullScreenSnip -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# Remove old exe
if (Test-Path $output) { Remove-Item $output -Force }

# Compile
& $csc /target:winexe /out:$output /r:System.Windows.Forms.dll /r:System.Drawing.dll $source

if (Test-Path $output) {
    Write-Host "✅ COMPILED SUCCESSFULLY: $((Get-Item $output).Length) bytes" -ForegroundColor Green
    Write-Host "Starting the fixed version..." -ForegroundColor Cyan
    Start-Process $output
} else {
    Write-Host "❌ COMPILE FAILED" -ForegroundColor Red
    exit 1
}