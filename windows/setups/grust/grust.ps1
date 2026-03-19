<#
.SYNOPSIS
    grust - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm https://pkgx.sh | iex; $env:PATH = "$env:USERPROFILE\.pkgx\pkgx.sh\v*\bin;" + $env:PATH; Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile "$env:TEMP\rustup-init.exe"; & "$env:TEMP\rustup-init.exe" -y --default-toolchain stable; Remove-Item "$env:TEMP\rustup-init.exe"; $env:PATH = "$env:USERPROFILE\.cargo\bin;" + $env:PATH; [Environment]::SetEnvironmentVariable('PATH', "$env:USERPROFILE\.pkgx\pkgx.sh\v*\bin;" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User'); [Environment]::SetEnvironmentVariable('PATH', "$env:USERPROFILE\.cargo\bin;" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User'); rustc --version; cargo --version
