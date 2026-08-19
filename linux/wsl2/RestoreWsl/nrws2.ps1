# Exports (syncs) the current WSL distribution to the localai archive,
# deleting the older localai.tar and replacing it with a fresh export.
function nrws2 {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
    param(
        [string] $Distribution = 'localai',
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

        if (-not $PSCmdlet.ShouldProcess($Distribution, "Export WSL distribution to '$ArchivePath' (replaces the older archive)")) {
            return
        }

        $progressId = 7552
        try {
            Write-Progress -Id $progressId -Activity 'WSL export' -Status 'Inspecting registered distributions' -PercentComplete 10
            $registered = @(
                & $wsl --list --quiet | ForEach-Object {
                    (([string] $_) -replace [string][char]0, '').Trim()
                } | Where-Object { $_ }
            )
            if ($LASTEXITCODE -ne 0) { throw "WSL distribution inventory failed with exit code $LASTEXITCODE." }
            if ($registered -notcontains $Distribution) {
                throw "WSL distribution '$Distribution' is not registered - nothing to export."
            }

            if (Test-Path -LiteralPath $ArchivePath) {
                Write-Progress -Id $progressId -Activity 'WSL export' -Status "Removing older archive '$ArchivePath'" -PercentComplete 35
                Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction Stop
            }
            $parent = Split-Path -Parent $ArchivePath
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }

            Write-Progress -Id $progressId -Activity 'WSL export' -Status "Exporting '$Distribution' to '$ArchivePath'" -PercentComplete 60
            & $wsl --export $Distribution $ArchivePath
            if ($LASTEXITCODE -ne 0) { throw "WSL export failed with exit code $LASTEXITCODE." }
            if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "WSL export did not produce an archive: $ArchivePath" }
            Write-Host "NRWS2_OK distribution='$Distribution' archive='$ArchivePath'" -ForegroundColor Green
        } finally {
            Write-Progress -Id $progressId -Activity 'WSL export' -Completed
        }
    } finally {
        $ConfirmPreference = $previousConfirmPreference
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    & 'nrws2' @args
}
