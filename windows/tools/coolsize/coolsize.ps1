<#
.SYNOPSIS
    coolsize
#>
Write-Host ""
    Write-Host "=== COOLING MODE STATUS ===" -ForegroundColor Cyan

    # ASUS Throttle Mode
    $iniPath = "C:\ProgramData\ASUS\ARMOURY CRATE Config\Data\InitialSetting.ini"
    if (Test-Path $iniPath) {
        $content = Get-Content $iniPath -Raw
        if ($content -match 'ThrottleModeOnAC=(\d)') {
            $mode = switch ($matches[1]) { "0" { "Silent" } "1" { "Performance" } "2" { "Turbo" } default { "Unknown" } }
            Write-Host "[THROTTLE] $mode (AC)" -ForegroundColor $(if($mode -eq "Silent"){"Green"}elseif($mode -eq "Turbo"){"Magenta"}else{"Yellow"})
        }
    }

    # Power Plan
    $activePlan = (powercfg /getactivescheme) -replace '.*\(|\).*', ''
    Write-Host "[POWER] $activePlan" -ForegroundColor $(if($activePlan -match "Nuclear"){"Magenta"}elseif($activePlan -match "Ultimate"){"Yellow"}else{"Green"})

    # CPU State - query MIN and MAX separately, join array to string for regex
    $minState = 0; $maxState = 100
    $minQuery = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>$null) -join "`n"
    $maxQuery = (powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>$null) -join "`n"
    if ($minQuery -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $minState = [int]("0x$($matches[1])") }
    if ($maxQuery -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { $maxState = [int]("0x$($matches[1])") }
    Write-Host "[CPU] $minState% - $maxState%" -ForegroundColor $(if($maxState -le 50){"Green"}elseif($maxState -le 80){"Yellow"}else{"Cyan"})

    # GPU Power Limit
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $gpuInfo = nvidia-smi --query-gpu=power.draw,power.max_limit,temperature.gpu --format=csv,noheader,nounits 2>$null
        if ($gpuInfo) {
            $parts = $gpuInfo -split ','
            $powerDraw = [math]::Round([float]$parts[0].Trim())
            $powerMax = [math]::Round([float]$parts[1].Trim())
            $temp = $parts[2].Trim()
            $tempColor = if ([int]$temp -lt 50) { "Green" } elseif ([int]$temp -lt 70) { "Yellow" } else { "Red" }
            Write-Host "[GPU] Draw: ${powerDraw}W / Max: ${powerMax}W | Temp: ${temp}C" -ForegroundColor $tempColor
        }
    }

    # Memory
    $mem = Get-CimInstance -ClassName Win32_OperatingSystem
    $freeGB = [math]::Round($mem.FreePhysicalMemory / 1MB, 1)
    $totalGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)
    Write-Host "[MEMORY] ${freeGB}GB free / ${totalGB}GB total" -ForegroundColor $(if($freeGB -gt 20){"Green"}elseif($freeGB -gt 10){"Yellow"}else{"Red"})

    Write-Host "[TIERS] min(silent)|2|3|4|5|6|7|8|9|max(TURBO)" -ForegroundColor DarkCyan
    Write-Host "[FEATURES] Throttle|Power|CPUState|GPUPower|Cleanup" -ForegroundColor DarkGray
    Write-Host ""
