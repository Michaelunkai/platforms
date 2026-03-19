<#
.SYNOPSIS
    gamesize - PowerShell utility script
.NOTES
    Original function: gamesize
    Extracted: 2026-02-19 20:20
#>
Write-Host "`n=== GAMING MODE STATUS ===" -ForegroundColor Cyan

    # Power plan
    $activePlan = powercfg /getactivescheme
    $planName = if ($activePlan -match '\(([^)]+)\)') { $matches[1] } else { "Unknown" }
    Write-Host "[POWER] $planName" -ForegroundColor Yellow

    # Game Mode
    $gameMode = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -ErrorAction SilentlyContinue).AutoGameModeEnabled
    Write-Host "[GAMEMODE] $(if($gameMode -eq 1){'ON'}else{'OFF'})" -ForegroundColor $(if($gameMode -eq 1){"Green"}else{"DarkGray"})

    # GPU Scheduling
    $hwSched = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue).HwSchMode
    Write-Host "[GPU SCHED] $(if($hwSched -eq 2){'ON'}else{'OFF'})" -ForegroundColor $(if($hwSched -eq 2){"Magenta"}else{"DarkGray"})

    # Memory info
    $mem = Get-CimInstance Win32_OperatingSystem
    $freeGB = [math]::Round($mem.FreePhysicalMemory / 1MB, 1)
    $totalGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)
    $usedPct = [math]::Round((1 - ($freeGB / $totalGB)) * 100)
    Write-Host "[MEMORY] ${freeGB}GB free / ${totalGB}GB total (${usedPct}% used)" -ForegroundColor $(if($usedPct -gt 80){"Red"}elseif($usedPct -gt 60){"Yellow"}else{"Green"})

    # GPU info
    Write-Host "[GPU] RTX 4090 + AMD 780M" -ForegroundColor Cyan

    # CPU Priority
    $priSep = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -ErrorAction SilentlyContinue).Win32PrioritySeparation
    $cpuBoost = if ($priSep -eq 38) { "MAX" } elseif ($priSep -eq 26) { "ON" } else { "Default" }
    Write-Host "[CPU BOOST] $cpuBoost" -ForegroundColor $(if($cpuBoost -eq "MAX"){"Cyan"}elseif($cpuBoost -eq "ON"){"Yellow"}else{"DarkGray"})

    Write-Host "[TIERS] min(chill)|2|3|4|5|6|7|8|9|max(PERF)" -ForegroundColor DarkCyan
    Write-Host "[FEATURES] PowerPlan|GameMode|GPUSched|Bloat|Memory|CPUBoost" -ForegroundColor DarkGray
    Write-Host ""
