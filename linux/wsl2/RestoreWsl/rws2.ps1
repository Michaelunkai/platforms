# Generated for the localai.tar variant of rws (2026-08-19).
function rws2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.tar',
        [switch] $Force
    )

    $previousConfirmPreference = $ConfirmPreference
    try {
        if ($Force) {
            $ConfirmPreference = 'None'
        }

        $windowsRoot = if ($env:WINDIR) { $env:WINDIR } elseif ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
        $wsl = Join-Path $windowsRoot 'System32\wsl.exe'
        if (-not (Test-Path -LiteralPath $wsl -PathType Leaf)) { throw "WSL executable not found: $wsl" }
        if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "WSL archive not found: $ArchivePath" }

        if (-not $PSCmdlet.ShouldProcess($Distribution, "Unregister and restore WSL distribution from '$ArchivePath'")) {
            return
        }

        $progressId = 7532
        try {
            Write-Progress -Id $progressId -Activity 'WSL restore' -Status 'Inspecting registered distributions' -PercentComplete 5
            $registered = @(
                & $wsl --list --quiet | ForEach-Object {
                    (([string] $_) -replace [string][char]0, '').Trim()
                } | Where-Object { $_ }
            )
            if ($LASTEXITCODE -ne 0) { throw "WSL distribution inventory failed with exit code $LASTEXITCODE." }
            $exists = $registered -contains $Distribution

            if ($exists) {
                Write-Progress -Id $progressId -Activity 'WSL restore' -Status "Terminating '$Distribution'" -PercentComplete 20
                & $wsl --terminate $Distribution
                if ($LASTEXITCODE -ne 0) { throw "WSL terminate failed with exit code $LASTEXITCODE." }
                Write-Progress -Id $progressId -Activity 'WSL restore' -Status "Unregistering '$Distribution'" -PercentComplete 35
                & $wsl --unregister $Distribution
                if ($LASTEXITCODE -ne 0) { throw "WSL unregister failed with exit code $LASTEXITCODE." }
            }

            if (Test-Path -LiteralPath $InstallRoot) {
                Write-Progress -Id $progressId -Activity 'WSL restore' -Status "Clearing import root '$InstallRoot'" -PercentComplete 55
                if ($PSCmdlet.ShouldProcess($InstallRoot, 'Remove old WSL import root')) {
                    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction Stop
                }
            }
            $parent = Split-Path -Parent $InstallRoot
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }

            Write-Progress -Id $progressId -Activity 'WSL restore' -Status "Importing '$Distribution' from verified archive" -PercentComplete 75
            & $wsl --import $Distribution $InstallRoot $ArchivePath
            if ($LASTEXITCODE -ne 0) { throw "WSL import failed with exit code $LASTEXITCODE." }
            Write-Progress -Id $progressId -Activity 'WSL restore' -Status 'Verifying restored distribution' -PercentComplete 95
            $verified = @(
                & $wsl --list --quiet | ForEach-Object {
                    (([string] $_) -replace [string][char]0, '').Trim()
                } | Where-Object { $_ }
            )
            if ($LASTEXITCODE -ne 0 -or -not ($verified -contains $Distribution)) {
                throw "WSL restore verification failed for '$Distribution'."
            }
            Write-Host "RWS2_OK distribution='$Distribution' root='$InstallRoot' archive='$ArchivePath'" -ForegroundColor Green
        } finally {
            Write-Progress -Id $progressId -Activity 'WSL restore' -Completed
        }
    } finally {
        $ConfirmPreference = $previousConfirmPreference
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'rws2' @args
}
