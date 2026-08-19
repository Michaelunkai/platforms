# Restores the localai WSL distribution from the fast VHD archive.
# (A .tar archive is also supported when the path ends in .tar.)
function rws2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
        [string] $InstallRoot = 'C:\wsl2\localai',
        [string] $ArchivePath = 'F:\backup\linux\wsl\localai.vhd',
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

        # Fast VHD is preferred; fall back to a .tar bootstrap archive when the
        # .vhd does not exist yet (e.g. the first restore from an old export).
        if ($ArchivePath -match '\.vhd(?:x)?$' -and -not (Test-Path -LiteralPath $ArchivePath)) {
            $tarFallback = [System.IO.Path]::ChangeExtension($ArchivePath, '.tar')
            if (Test-Path -LiteralPath $tarFallback) {
                $ArchivePath = $tarFallback
            }
        }
        if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "WSL archive not found: $ArchivePath" }

        if (-not $PSCmdlet.ShouldProcess($Distribution, "Unregister and restore WSL distribution from '$ArchivePath'")) {
            return
        }

        $registered = @(
            & $wsl --list --quiet | ForEach-Object {
                (([string] $_) -replace [string][char]0, '').Trim()
            } | Where-Object { $_ }
        )
        if ($LASTEXITCODE -ne 0) { throw "WSL distribution inventory failed with exit code $LASTEXITCODE." }

        if ($registered -contains $Distribution) {
            & $wsl --unregister $Distribution
            if ($LASTEXITCODE -ne 0) { throw "WSL unregister failed with exit code $LASTEXITCODE." }
        }

        if (Test-Path -LiteralPath $InstallRoot) {
            if ($PSCmdlet.ShouldProcess($InstallRoot, 'Remove old WSL import root')) {
                Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction Stop
            }
        }
        $parent = Split-Path -Parent $InstallRoot
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }

        if ($ArchivePath -match '\.vhd(?:x)?$') {
            & $wsl --import $Distribution $InstallRoot $ArchivePath --vhd
        } else {
            & $wsl --import $Distribution $InstallRoot $ArchivePath
        }
        if ($LASTEXITCODE -ne 0) { throw "WSL import failed with exit code $LASTEXITCODE." }

        Write-Host "RWS2_OK distribution='$Distribution' root='$InstallRoot' archive='$ArchivePath'" -ForegroundColor Green
    } finally {
        $ConfirmPreference = $previousConfirmPreference
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'rws2' @args
}
