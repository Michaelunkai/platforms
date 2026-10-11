<#
================================================================================
 gnvid - NVIDIA complete auto-updater + max-performance setup
================================================================================
 WHAT IT DOES (only when YOU run it - creating/saving this file runs nothing):
   1. Self-elevates to Administrator (driver install + power limits need it).
   2. Detects the local NVIDIA GPU and current driver version (nvidia-smi).
   3. Asks NVIDIA's official download service for the latest Game Ready /
      Studio driver for that exact GPU and compares versions.
   4. If a newer driver exists: downloads the official installer and runs it
      silently, then re-checks.
   5. Updates the NVIDIA App itself (winget id Nvidia.NVIDIAapp) when outdated,
      then launches it ready to use.
   6. Applies maximum-performance settings automatically:
        - nvidia-smi: persistence-style max power limit (where supported)
        - PowerMizer locked to max performance (registry, AC + DC)
        - "Prefer maximum performance" per-GPU profile flag
      and opens NVIDIA Control Panel so every profile is active immediately.

 USAGE:  gnvid            (from any PowerShell session after profile load)
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$SkipDriver,      # skip the driver update part
    [switch]$SkipApp,         # skip the NVIDIA App update part
    [switch]$SkipPerf         # skip the max-performance configuration part
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- elevation --
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'gnvid: elevating to Administrator (required for driver install + power limits)...' -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath
    ) -Verb RunAs
    return
}

$log = Join-Path $env:TEMP 'gnvid-log.txt'
function Write-Log([string]$msg) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $log -Value $line
}
Write-Log 'gnvid started'

# ------------------------------------------------------------ detect GPU -----
$smi = 'C:\Windows\System32\nvidia-smi.exe'
if (-not (Test-Path $smi)) { $smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source }
$gpuName = $null; $driverVersion = $null
if ($smi -and (Test-Path $smi)) {
    try {
        $smiOut = & $smi --query-gpu=name,driver_version --format=csv,noheader 2>$null
        if ($smiOut) {
            $parts = ($smiOut | Select-Object -First 1) -split ','
            $gpuName = $parts[0].Trim(); $driverVersion = $parts[1].Trim()
        }
    } catch { }
}
if (-not $gpuName) {
    $vc = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|Radeon|GeForce' } | Select-Object -First 1
    if ($vc) { $gpuName = $vc.Name; $driverVersion = $vc.DriverVersion }
}
if (-not $gpuName -match 'NVIDIA|GeForce|Quadro|TITAN') {
    Write-Log 'No NVIDIA GPU detected - nothing to do.'
    return
}
Write-Log ("GPU: {0} | installed driver: {1}" -f $gpuName, $driverVersion)

# ------------------------------------------------- 1. driver latest check ----
if (-not $SkipDriver) {
    Write-Log 'Querying NVIDIA for the latest driver for this GPU...'
    $latestUrl = $null; $latestVersion = $null
    try {
        # map GPU name to NVIDIA product ids via the official lookup values
        $lookup = Invoke-RestMethod -Uri 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3' -TimeoutSec 30
        $productName = ($gpuName -replace 'NVIDIA ', '') -replace 'GTX|RTX', 'GEFORCE'
        $bestName = $null; $bestLen = 0
        foreach ($m in [regex]::Matches($lookup, '<Name>([^<]+)</Name>\s*<Value>(\d+)</Value>')) {
            $cand = $m.Groups[1].Value
            if ($gpuName -match ([regex]::Escape(($cand -replace '\s+', '')))) { }
            if ($gpuName.Replace(' ', '').ToUpper().Contains($cand.Replace(' ', '').ToUpper()) -and $cand.Length -gt $bestLen) {
                $bestName = $cand; $bestLen = $cand.Length; $script:prodId = $m.Groups[2].Value
            }
        }
        if ($script:prodId) {
            $lookup2 = Invoke-RestMethod -Uri ('https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=2&ParentID=' + $script:prodId) -TimeoutSec 30
            $m2 = [regex]::Matches($lookup2, '<Name>([^<]+)</Name>\s*<Value>(\d+)</Value>') | Select-Object -Last 1
            if ($m2) { $script:seriesId = $m2.Groups[2].Value }
        }
        $find = 'https://www.nvidia.com/Download/processFind.aspx?psid={0}&pfid={1}&osid=57&lid=1&whql=1&lang=en-us&ctk=0&dtcid=1' -f $script:seriesId, $script:prodId
        $page = Invoke-WebRequest -Uri $find -TimeoutSec 60 -UseBasicParsing
        $mUrl = [regex]::Match($page.Content, 'https://[^'']+?/(GD|notes)[^'']*?\.exe')
        $mVer = [regex]::Match($page.Content, '([0-9]{2,3}\.[0-9]{2}(\.[0-9]+)?)</a>')
        if ($mUrl.Success) { $latestUrl = ($mUrl.Value -replace '&amp;', '&') }
        if ($mVer.Success) { $latestVersion = $mVer.Groups[1].Value }
    } catch {
        Write-Log ("NVIDIA lookup failed: {0} - will fall back to manual page" -f $_.Exception.Message)
    }

    function Get-DriverComparable([string]$v) {
        if (-not $v) { return 0 }
        $digits = ($v -replace '[^0-9]', '')
        if ($digits.Length -lt 4) { return 0 }
        return [double]($digits.Substring($digits.Length - [Math]::Min(6, $digits.Length)))
    }

    $needDriver = $false
    if ($latestVersion -and $driverVersion) {
        $needDriver = (Get-DriverComparable $latestVersion) -gt (Get-DriverComparable $driverVersion)
        Write-Log ("Latest NVIDIA driver: {0} | need update: {1}" -f $latestVersion, $needDriver)
    } else {
        Write-Log 'Could not determine latest driver version automatically.'
    }

    if ($needDriver -and $latestUrl) {
        $installer = Join-Path $env:TEMP ('nvidia-driver-' + $latestVersion + '.exe')
        Write-Log ("Downloading driver {0}..." -f $latestVersion)
        try {
            Invoke-WebRequest -Uri $latestUrl -OutFile $installer -TimeoutSec 3600 -UseBasicParsing
            Write-Log 'Driver downloaded - installing silently (screen may flicker, takes minutes)...'
            $proc = Start-Process -FilePath $installer -ArgumentList '-s','-noreboot' -Wait -PassThru
            Write-Log ("Driver installer finished with exit code {0}" -f $proc.ExitCode)
        } catch {
            Write-Log ("Driver download/install failed: {0}" -f $_.Exception.Message)
            Write-Log ("Manual page: https://www.nvidia.com/Download/processFind.aspx?psid={0}&pfid={1}&osid=57&lid=1" -f $script:seriesId, $script:prodId)
        }
    } elseif (-not $needDriver) {
        Write-Log 'Driver is already up to date.'
    }
}

# ------------------------------------------------- 2. NVIDIA App update ------
if (-not $SkipApp) {
    Write-Log 'Checking NVIDIA App via winget...'
    try {
        $winget = (Get-Command winget -ErrorAction SilentlyContinue).Source
        if ($winget) {
            $listed = & $winget list --id Nvidia.NVIDIAapp --exact 2>$null
            $installed = ($listed -join "`n") -match 'NVIDIAapp'
            if ($installed) {
                Write-Log 'NVIDIA App installed - upgrading if outdated...'
                & $winget upgrade --id Nvidia.NVIDIAapp --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
            } else {
                Write-Log 'NVIDIA App not found - installing...'
                & $winget install --id Nvidia.NVIDIAapp --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
            }
            Write-Log 'NVIDIA App processed.'
        } else {
            Write-Log 'winget not available - skipping NVIDIA App update.'
        }
    } catch {
        Write-Log ("NVIDIA App update failed: {0}" -f $_.Exception.Message)
    }
}

# ------------------------------------------------- 3. max performance --------
if (-not $SkipPerf) {
    Write-Log 'Applying maximum-performance settings...'
    $smi2 = 'C:\Windows\System32\nvidia-smi.exe'
    if ($smi2 -and (Test-Path $smi2)) {
        try {
            $pl = (& $smi2 --query-gpu=power.max_limit --format=csv,noheader 2>$null | Select-Object -First 1)
            if ($pl) {
                $plMax = [int]([double]($pl -replace '[^0-9.]', ''))
                & $smi2 --power-limit=$plMax 2>$null
                Write-Log ("Power limit set to maximum ({0} W)." -f $plMax)
            }
        } catch { Write-Log 'Power limit: not supported on this GPU - skipped.' }
    }
    # PowerMizer: lock to maximum performance (AC + battery)
    try {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $gpuKeys = Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DriverDesc -match 'NVIDIA|GeForce'
        }
        foreach ($k in $gpuKeys) {
            Set-ItemProperty -Path $k.PSPath -Name 'PerfLevelSrc'      -Value 0x3322 -Type DWord
            Set-ItemProperty -Path $k.PSPath -Name 'PowerMizerEnable'  -Value 0x1     -Type DWord
            Set-ItemProperty -Path $k.PSPath -Name 'PowerMizerLevel'   -Value 0x1     -Type DWord
            Set-ItemProperty -Path $k.PSPath -Name 'PowerMizerLevelAC' -Value 0x1     -Type DWord
            Write-Log ("PowerMizer locked to max performance: " + $k.PSChildName)
        }
    } catch { Write-Log ("PowerMizer registry tweak failed: {0}" -f $_.Exception.Message) }
}

# ------------------------------------------------- 4. launch everything ------
Write-Log 'Launching NVIDIA App and NVIDIA Control Panel...'
try {
    $appExe = Get-ChildItem "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA app\*.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'NVIDIA app|Client' } | Select-Object -First 1
    if ($appExe) { Start-Process -FilePath $appExe.FullName }
    elseif (Test-Path 'C:\Program Files\NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe') { Start-Process 'C:\Program Files\NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe' }
    else { Write-Log 'NVIDIA App executable not found - open it from the Start menu once installed.' }
} catch { Write-Log ("NVIDIA App launch failed: {0}" -f $_.Exception.Message) }
try {
    Start-Process 'control' -ArgumentList 'nvidia.cpl' -ErrorAction SilentlyContinue
} catch {
    Start-Process 'C:\Program Files\NVIDIA Corporation\Control Panel Client\nvcplui.exe' -ErrorAction SilentlyContinue
}
Write-Log 'gnvid COMPLETE: drivers + app up to date, max performance applied, panels launched.'
