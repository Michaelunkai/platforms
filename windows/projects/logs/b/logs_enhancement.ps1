# ============================================================================
# COMPREHENSIVE PERFORMANCE DETECTION v5.0 - ULTIMATE EDITION
# Detects EVERYTHING that affects: Network, Gaming, Docker, Multitasking
# ============================================================================

# ============================================================================
# NETWORK PERFORMANCE BOTTLENECKS - DEEP ANALYSIS
# ============================================================================
Section "NETWORK PERFORMANCE & BANDWIDTH ISSUES"
Write-Host "Checking network performance bottlenecks..." -ForegroundColor Magenta

try {
    # DNS Resolution Performance
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -EA 0 | Where-Object { $_.ServerAddresses.Count -gt 0 }
    foreach ($adapter in $dnsServers) {
        foreach ($dns in $adapter.ServerAddresses) {
            try {
                $dnsTest = Measure-Command { Resolve-DnsName "google.com" -Server $dns -EA 0 }
                if ($dnsTest.TotalMilliseconds -gt 100) {
                    Problem "SLOW DNS: Server $dns responding in $([math]::Round($dnsTest.TotalMilliseconds))ms (threshold: 100ms)"
                }
                if ($dnsTest.TotalMilliseconds -gt 500) {
                    CriticalProblem "CRITICAL DNS LATENCY: Server $dns is $([math]::Round($dnsTest.TotalMilliseconds))ms - causing major slowdowns"
                }
            } catch {
                CriticalProblem "DNS FAILURE: Server $dns is unreachable or timing out"
            }
        }
    }

    # DNS Cache Issues
    $dnsCacheSize = (Get-DnsClientCache -EA 0 | Measure-Object).Count
    if ($dnsCacheSize -gt 5000) {
        Problem "DNS CACHE BLOAT: $dnsCacheSize entries - may cause lookup delays"
    }

    # Failed DNS resolutions in cache
    $failedDNS = Get-DnsClientCache -EA 0 | Where-Object { $_.Status -ne 0 } | Measure-Object
    if ($failedDNS.Count -gt 10) {
        Problem "FAILED DNS ENTRIES: $($failedDNS.Count) failed lookups cached - slowing resolution"
    }

    # Network adapter performance
    $adapters = Get-NetAdapter -EA 0 | Where-Object { $_.Status -eq 'Up' -and $_.MediaType -notmatch 'Bluetooth' }
    foreach ($adapter in $adapters) {
        # Check for errors
        $stats = Get-NetAdapterStatistics -Name $adapter.Name -EA 0
        if ($stats) {
            $errorRate = ($stats.ReceivedUnicastPackets + $stats.SentUnicastPackets)
            if ($errorRate -gt 0) {
                $pctErrors = (($stats.ReceivedPacketErrors + $stats.OutboundPacketErrors) / $errorRate) * 100
                if ($pctErrors -gt 1) {
                    CriticalProblem "NETWORK ERRORS: $($adapter.Name) has $([math]::Round($pctErrors, 2))% packet errors"
                }
            }
        }

        # Check link speed vs capability
        if ($adapter.LinkSpeed -and $adapter.LinkSpeed -ne "0 bps") {
            $linkSpeedGbps = [regex]::Match($adapter.LinkSpeed, '(\d+)\s*Gbps').Groups[1].Value
            $linkSpeedMbps = [regex]::Match($adapter.LinkSpeed, '(\d+)\s*Mbps').Groups[1].Value

            if ($linkSpeedMbps -and [int]$linkSpeedMbps -lt 100) {
                Problem "SLOW LINK SPEED: $($adapter.Name) running at $($adapter.LinkSpeed) - should be 1Gbps+"
            }
        }

        # Check for negotiation issues
        $advProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -EA 0
        $speedDuplex = $advProp | Where-Object { $_.RegistryKeyword -eq 'SpeedDuplex' }
        if ($speedDuplex -and $speedDuplex.DisplayValue -notmatch 'Auto') {
            Problem "NETWORK CONFIG: $($adapter.Name) speed/duplex is MANUAL - may cause slowdowns"
        }
    }

    # QoS Policy Issues (Windows Quality of Service can throttle)
    $qosPolicies = Get-NetQosPolicy -EA 0
    foreach ($policy in $qosPolicies) {
        if ($policy.ThrottleRateActionBitsPerSecond -gt 0) {
            $mbps = [math]::Round($policy.ThrottleRateActionBitsPerSecond / 1MB, 2)
            Problem "QoS THROTTLING: Policy '$($policy.Name)' limiting to $mbps Mbps"
        }
    }

    # Windows Update Delivery Optimization bandwidth limit
    $doConfig = Get-DeliveryOptimizationPerfSnap -EA 0
    if ($doConfig) {
        $downloadMode = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -EA 0).DODownloadMode
        if ($downloadMode -eq 3) {
            Problem "DELIVERY OPTIMIZATION: May be consuming bandwidth in background"
        }
    }

    # TCP/IP Stack Issues
    $tcpSettings = Get-NetTCPSetting -EA 0
    foreach ($setting in $tcpSettings) {
        if ($setting.AutoTuningLevelLocal -eq 'Disabled') {
            CriticalProblem "TCP WINDOW AUTO-TUNING DISABLED: Severely limits download speeds"
        }
        if ($setting.ScalingHeuristics -eq 'Disabled') {
            Problem "TCP SCALING HEURISTICS DISABLED: May reduce throughput"
        }
    }

    # Network Throttling Index (Windows can throttle multimedia streaming)
    $throttle = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -EA 0
    if ($throttle.NetworkThrottlingIndex -ne 4294967295 -and $throttle.NetworkThrottlingIndex -ne $null) {
        Problem "NETWORK THROTTLING: Index is $($throttle.NetworkThrottlingIndex) (should be 0xFFFFFFFF for gaming/streaming)"
    }

    # Large Send Offload issues
    $adapters | ForEach-Object {
        $lso = Get-NetAdapterLso -Name $_.Name -EA 0
        if ($lso -and -not $lso.V2IPv4Enabled -and -not $lso.V2IPv6Enabled) {
            Problem "LSO DISABLED: $($_.Name) Large Send Offload off - may reduce throughput"
        }
    }

    # RSS (Receive Side Scaling) for multi-core performance
    $adapters | ForEach-Object {
        $rss = Get-NetAdapterRss -Name $_.Name -EA 0
        if ($rss -and -not $rss.Enabled) {
            Problem "RSS DISABLED: $($_.Name) not using multi-core for network - hurts performance"
        }
    }

    # Network Location Awareness Service (affects connectivity detection)
    $nlaSvc = Get-Service -Name "NlaSvc" -EA 0
    if ($nlaSvc -and $nlaSvc.Status -ne 'Running') {
        CriticalProblem "NETWORK LOCATION AWARENESS: Service stopped - network detection broken"
    }

    # Windows Firewall rules that block legitimate traffic
    $blockRules = Get-NetFirewallRule -EA 0 | Where-Object { $_.Enabled -eq $true -and $_.Action -eq 'Block' -and $_.Direction -eq 'Outbound' }
    if ($blockRules.Count -gt 50) {
        Problem "FIREWALL: $($blockRules.Count) outbound block rules - may interfere with apps"
    }

    # Proxy Settings that slow down connections
    $proxySettings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -EA 0
    if ($proxySettings.ProxyEnable -eq 1) {
        $proxyServer = $proxySettings.ProxyServer
        Problem "PROXY ENABLED: All traffic routing through $proxyServer - adds latency"
    }

    # SMB signing overhead (affects file sharing performance)
    $smbClient = Get-SmbClientConfiguration -EA 0
    if ($smbClient.RequireSecuritySignature) {
        Problem "SMB SIGNING REQUIRED: Adds CPU overhead to file transfers - impacts NAS/network drives"
    }

    # Router/Gateway connectivity issues
    $defaultGateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -EA 0 | Select-Object -First 1
    if ($defaultGateway) {
        $pingTest = Test-Connection -ComputerName $defaultGateway.NextHop -Count 2 -EA 0
        if (-not $pingTest) {
            CriticalProblem "GATEWAY UNREACHABLE: Default gateway $($defaultGateway.NextHop) not responding"
        } else {
            $avgPing = ($pingTest | Measure-Object -Property ResponseTime -Average).Average
            if ($avgPing -gt 10) {
                Problem "GATEWAY LATENCY: $([math]::Round($avgPing))ms to router - should be <5ms (cable/config issue?)"
            }
        }
    }

    # MTU Size issues (can cause fragmentation = slow transfers)
    $adapters | ForEach-Object {
        $netipInterface = Get-NetIPInterface -InterfaceAlias $_.Name -AddressFamily IPv4 -EA 0
        if ($netipInterface -and $netipInterface.NlMtu -lt 1500) {
            Problem "LOW MTU: $($_.Name) MTU is $($netipInterface.NlMtu) - may cause fragmentation slowdowns"
        }
    }

    # IPv6 transition technologies causing delays
    $tunnelAdapters = Get-NetAdapter -EA 0 | Where-Object { $_.InterfaceDescription -match 'Teredo|6to4|ISATAP' -and $_.Status -eq 'Up' }
    if ($tunnelAdapters) {
        Problem "IPv6 TUNNELING ACTIVE: $($tunnelAdapters.Count) tunnel adapter(s) - can cause connection delays"
    }

} catch {
    Write-Host "  Error checking network performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# GAMING & MULTITASKING PERFORMANCE ISSUES
# ============================================================================
Section "GAMING & MULTITASKING PERFORMANCE"
Write-Host "Checking gaming/multitasking performance issues..." -ForegroundColor Magenta

try {
    # CPU Thermal Throttling
    try {
        $thermalInfo = Get-WmiObject -Namespace "root/wmi" -Class "MSAcpi_ThermalZoneTemperature" -EA 0
        if ($thermalInfo) {
            foreach ($zone in $thermalInfo) {
                $tempC = ($zone.CurrentTemperature / 10) - 273.15
                if ($tempC -gt 85) {
                    CriticalProblem "CPU THERMAL THROTTLING: Zone $($zone.InstanceName) at $([math]::Round($tempC))°C - performance severely degraded"
                } elseif ($tempC -gt 75) {
                    Problem "CPU RUNNING HOT: Zone $($zone.InstanceName) at $([math]::Round($tempC))°C - may throttle soon"
                }
            }
        }
    } catch {}

    # Power Throttling (Windows 11 feature that limits background apps)
    $powerThrottling = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -EA 0
    if ($powerThrottling -and $powerThrottling.PowerThrottlingOff -ne 1) {
        Problem "POWER THROTTLING ENABLED: Background apps throttled - may affect game performance"
    }

    # Core Parking (CPUs parked = less performance)
    $coreParking = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -Name "ValueMax" -EA 0
    if ($coreParking -and $coreParking.ValueMax -lt 100) {
        Problem "CORE PARKING ACTIVE: CPUs being parked - reduces multitasking performance"
    }

    # GPU Performance State
    try {
        $gpuDrivers = Get-WmiObject Win32_VideoController -EA 0
        foreach ($gpu in $gpuDrivers) {
            # Check driver age
            if ($gpu.DriverDate) {
                $driverDate = [Management.ManagementDateTimeConverter]::ToDateTime($gpu.DriverDate)
                $driverAge = (Get-Date) - $driverDate
                if ($driverAge.TotalDays -gt 180) {
                    Problem "OLD GPU DRIVER: $($gpu.Name) driver is $([math]::Round($driverAge.TotalDays)) days old - may have performance issues"
                }
            }

            # Check if GPU is in low power mode
            $gpuConfig = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" -EA 0
            if ($gpuConfig -and $gpuConfig.PP_ThermalControllerInitialized -eq 0) {
                Problem "GPU POWER STATE: May be in low-performance mode"
            }
        }
    } catch {}

    # TDR (Timeout Detection and Recovery) - GPU freezes/resets
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display'; StartTime=$last7d} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Id -eq 4101 -or $_.Message -match 'TDR|timeout|GPU.*reset|display driver.*stopped'
        } | ForEach-Object {
            CriticalProblem "GPU TDR EVENT: Display driver reset at $($_.TimeCreated) - causes frame drops/freezes"
        }
    } catch {}

    # DPC Latency (high DPC = stuttering/lag)
    try {
        $dpcEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=26; StartTime=$last7d} -EA 0 -MaxEvents 50
        if ($dpcEvents.Count -gt 5) {
            CriticalProblem "HIGH DPC LATENCY: $($dpcEvents.Count) events - causes audio crackling, frame drops, input lag"
        }
    } catch {}

    # High CPU usage processes (>80% sustained)
    $cpuHogs = Get-Process -EA 0 | Where-Object { $_.CPU -gt 30 } | Sort-Object CPU -Descending | Select-Object -First 5
    foreach ($proc in $cpuHogs) {
        if ($proc.Name -notmatch 'Idle|System') {
            Problem "HIGH CPU USAGE: $($proc.Name) using significant CPU - may impact game performance"
        }
    }

    # Memory Pressure (low available RAM)
    $mem = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($mem) {
        $memAvailMB = [math]::Round($mem.FreePhysicalMemory / 1024)
        $memTotalMB = [math]::Round($mem.TotalVisibleMemorySize / 1024)
        $memUsedPct = (($memTotalMB - $memAvailMB) / $memTotalMB) * 100

        if ($memUsedPct -gt 95) {
            CriticalProblem "CRITICAL MEMORY PRESSURE: $([math]::Round($memUsedPct))% used ($memAvailMB MB free) - swapping to disk"
        } elseif ($memUsedPct -gt 85) {
            Problem "HIGH MEMORY USAGE: $([math]::Round($memUsedPct))% used ($memAvailMB MB free) - may cause slowdowns"
        }
    }

    # Superfetch/SysMain causing disk thrashing
    $sysMain = Get-Service -Name "SysMain" -EA 0
    if ($sysMain -and $sysMain.Status -eq 'Running') {
        # Check if causing high disk usage
        try {
            $diskEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Disk'; Level=2,3; StartTime=$lastHour} -EA 0 -MaxEvents 20
            if ($diskEvents.Count -gt 10) {
                Problem "SUPERFETCH (SysMain): May be causing disk thrashing - impacts game loading"
            }
        } catch {}
    }

    # Game Mode Issues
    $gameMode = Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -EA 0
    if ($gameMode -and $gameMode.AllowAutoGameMode -eq 0) {
        Problem "GAME MODE DISABLED: Not optimizing for gaming performance"
    }

    # Game DVR/Recording overhead
    $gameDVR = Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -EA 0
    if ($gameDVR -and $gameDVR.GameDVR_Enabled -eq 1) {
        Problem "GAME DVR ENABLED: Background recording adds GPU/CPU overhead"
    }

    # Windows Search Indexing during gameplay
    $searchSvc = Get-Service -Name "WSearch" -EA 0
    if ($searchSvc -and $searchSvc.Status -eq 'Running') {
        try {
            $searchProc = Get-Process -Name "SearchIndexer" -EA 0
            if ($searchProc -and $searchProc.CPU -gt 5) {
                Problem "SEARCH INDEXING ACTIVE: Using CPU/Disk during potential gameplay"
            }
        } catch {}
    }

    # Full-screen optimizations (can cause input lag)
    $gameBarFSO = Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -EA 0
    if ($gameBarFSO -and $gameBarFSO.GameDVR_FSEBehaviorMode -ne 2) {
        Problem "FULLSCREEN OPTIMIZATIONS: Enabled - may cause input lag in some games"
    }

    # High-precision timer resolution (affects frame pacing)
    $timerResolution = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -EA 0
    if (-not $timerResolution) {
        Problem "TIMER RESOLUTION: Not optimized - may cause frame pacing issues"
    }

    # HPET (High Precision Event Timer) config
    try {
        $hpet = bcdedit /enum | Select-String "useplatformclock"
        if ($hpet -match "Yes") {
            Problem "HPET ENABLED: Can cause performance issues in some games/applications"
        }
    } catch {}

} catch {
    Write-Host "  Error checking gaming/multitasking performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# DOCKER & CONTAINER PERFORMANCE ISSUES
# ============================================================================
Section "DOCKER & CONTAINER PERFORMANCE"
Write-Host "Checking Docker & container performance..." -ForegroundColor Magenta

try {
    # HNS (Host Network Service) errors - affects Docker networking
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Hyper-V-VmSwitch','Hyper-V-Shared-VHDX','VMSMP'; StartTime=$last7d} -EA 0 -MaxEvents 200 | Where-Object {
            $_.Message -match 'HNS|IpNatHlpStopSharing|0x80070032|failed to delete|winnat'
        } | ForEach-Object {
            CriticalProblem "HNS ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }
    } catch {}

    # Docker Service State
    $dockerSvc = Get-Service -Name "com.docker.service" -EA 0
    if ($dockerSvc) {
        if ($dockerSvc.Status -ne 'Running') {
            Problem "DOCKER SERVICE: Not running - Docker won't work"
        }
    }

    # WSL2 Backend Issues (Docker Desktop uses WSL2)
    $wsl2 = Get-Service -Name "LxssManager" -EA 0
    if ($wsl2) {
        if ($wsl2.Status -ne 'Running') {
            CriticalProblem "WSL2: LxssManager service stopped - Docker Desktop won't function"
        }
    }

    # Hyper-V Virtual Switch Issues
    try {
        $vSwitches = Get-VMSwitch -EA 0
        foreach ($vSwitch in $vSwitches) {
            if ($vSwitch.SwitchType -eq 'External' -and -not $vSwitch.NetAdapterInterfaceDescription) {
                Problem "HYPER-V SWITCH: $($vSwitch.Name) not bound to network adapter - Docker networking broken"
            }
        }
    } catch {}

    # NAT Network Corruption
    $natNetworks = Get-NetNat -EA 0
    if ($natNetworks.Count -eq 0) {
        Problem "NO NAT NETWORKS: Docker may not have network connectivity"
    }

    # Check for conflicting NAT ranges
    $natRanges = @{}
    $natNetworks | ForEach-Object {
        if ($natRanges.ContainsKey($_.InternalIPInterfaceAddressPrefix)) {
            Problem "DUPLICATE NAT RANGE: $($_.InternalIPInterfaceAddressPrefix) used by multiple NAT instances"
        }
        $natRanges[$_.InternalIPInterfaceAddressPrefix] = $true
    }

    # Docker Storage Driver Issues
    try {
        if (Test-Path "C:\ProgramData\Docker\config\daemon.json") {
            $dockerConfig = Get-Content "C:\ProgramData\Docker\config\daemon.json" -Raw -EA 0 | ConvertFrom-Json -EA 0
            if ($dockerConfig.'storage-driver' -eq 'aufs') {
                Problem "DOCKER STORAGE DRIVER: Using AUFS - very slow on Windows, use overlay2"
            }
        }
    } catch {}

    # Memory/CPU limits for Docker
    try {
        $wslConfig = Get-Content "$env:USERPROFILE\.wslconfig" -EA 0
        if (-not $wslConfig) {
            Problem "WSL CONFIG: No .wslconfig found - Docker may use too much memory/CPU"
        } else {
            if ($wslConfig -notmatch 'memory\s*=') {
                Problem "WSL CONFIG: No memory limit - Docker can consume all RAM"
            }
            if ($wslConfig -notmatch 'processors\s*=') {
                Problem "WSL CONFIG: No CPU limit - Docker can use all cores"
            }
        }
    } catch {}

    # VirtualDisk Service (needed for Docker volumes)
    $vdiskSvc = Get-Service -Name "VirtualDisk" -EA 0
    if ($vdiskSvc -and $vdiskSvc.Status -ne 'Running') {
        CriticalProblem "VIRTUAL DISK SERVICE: Stopped - Docker volumes won't work"
    }

    # Hyper-V Components
    $hvFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -EA 0
    if ($hvFeature -and $hvFeature.State -ne 'Enabled') {
        Problem "HYPER-V: Not enabled - Docker Desktop requires Hyper-V"
    }

    # Containers Feature
    $containerFeature = Get-WindowsOptionalFeature -Online -FeatureName "Containers" -EA 0
    if ($containerFeature -and $containerFeature.State -ne 'Enabled') {
        Problem "CONTAINERS FEATURE: Not enabled - native containers won't work"
    }

    # HNS Data File Corruption
    if (Test-Path "C:\ProgramData\Microsoft\Windows\HNS\HNS.data") {
        $hnsData = Get-Item "C:\ProgramData\Microsoft\Windows\HNS\HNS.data" -EA 0
        if ($hnsData.Length -eq 0) {
            CriticalProblem "HNS DATA: Corrupted (zero size) - Docker networking completely broken"
        }
        # Check modification time - if very old, may be stale
        $hnsAge = (Get-Date) - $hnsData.LastWriteTime
        if ($hnsAge.TotalDays -gt 30) {
            Problem "HNS DATA: Not updated in $([math]::Round($hnsAge.TotalDays)) days - may be stale"
        }
    }

    # Docker Download Speed Issues (registry mirrors)
    try {
        if (Test-Path "C:\ProgramData\Docker\config\daemon.json") {
            $dockerConfig = Get-Content "C:\ProgramData\Docker\config\daemon.json" -Raw -EA 0 | ConvertFrom-Json -EA 0
            if (-not $dockerConfig.'registry-mirrors') {
                Problem "DOCKER REGISTRY: No mirrors configured - image pulls may be slow"
            }
        }
    } catch {}

} catch {
    Write-Host "  Error checking Docker/container performance: $_" -ForegroundColor DarkRed
}

# ============================================================================
# FREEZE, HANG & CRASH DETECTION - ULTIMATE
# ============================================================================
Section "SYSTEM FREEZE, HANG & CRASH DETECTION"
Write-Host "Checking for freeze/hang/crash causes..." -ForegroundColor Magenta

try {
    # DPC Watchdog Violations (causes freeze then BSOD)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 500 | Where-Object {
            $_.Message -match 'DPC.*watchdog|DPC.*timeout|DPC.*violation|clock interrupt.*not received'
        } | ForEach-Object {
            CriticalProblem "DPC WATCHDOG: $($_.TimeCreated) - causes system freezes/BSOD"
        }
    } catch {}

    # Storage Controller Resets (causes freeze during disk I/O)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=129; StartTime=$last7d} -EA 0 | ForEach-Object {
            CriticalProblem "DISK CONTROLLER RESET: $($_.TimeCreated) - causes freezes during disk activity"
        }
    } catch {}

    # Pagefile Exhaustion (causes freeze when RAM full)
    try {
        $pagefiles = Get-CimInstance Win32_PageFileUsage -EA 0
        foreach ($pf in $pagefiles) {
            $pfUsedPct = ($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100
            if ($pfUsedPct -gt 90) {
                CriticalProblem "PAGEFILE EXHAUSTION: $($pf.Name) at $([math]::Round($pfUsedPct))% - causes freezes"
            }
        }
    } catch {}

    # Disk Queue Length (high queue = freezing)
    $disks = Get-PhysicalDisk -EA 0
    foreach ($disk in $disks) {
        try {
            $diskPerf = Get-Counter "\PhysicalDisk($($disk.FriendlyName))\Avg. Disk Queue Length" -EA 0
            if ($diskPerf.CounterSamples.CookedValue -gt 2) {
                Problem "DISK QUEUE: $($disk.FriendlyName) queue length $([math]::Round($diskPerf.CounterSamples.CookedValue, 2)) - causes slowdowns"
            }
        } catch {}
    }

    # Disk Response Time
    Get-PhysicalDisk -EA 0 | ForEach-Object {
        try {
            $diskRead = Get-Counter "\PhysicalDisk($($_.FriendlyName))\Avg. Disk sec/Read" -EA 0
            if ($diskRead.CounterSamples.CookedValue -gt 0.1) {
                Problem "SLOW DISK: $($_.FriendlyName) read latency $([math]::Round($diskRead.CounterSamples.CookedValue * 1000))ms - causes freezes"
            }
        } catch {}
    }

    # Memory Leak Detection
    $processes = Get-Process -EA 0 | Where-Object { $_.WorkingSet64 -gt 500MB } | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    foreach ($proc in $processes) {
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB)
        if ($memMB -gt 2000) {
            Problem "MEMORY LEAK SUSPECT: $($proc.Name) using $memMB MB RAM"
        }
    }

    # Handle Leak Detection
    $processes | Where-Object { $_.HandleCount -gt 10000 } | ForEach-Object {
        Problem "HANDLE LEAK: $($_.Name) has $($_.HandleCount) handles - may cause freezes"
    }

    # GDI Object Leak (causes Windows UI to freeze)
    try {
        $gdiLeaks = Get-Process -EA 0 | Where-Object { $_.HandleCount -gt 5000 } | ForEach-Object {
            try {
                $gdiCount = (Get-Counter "\Process($($_.Name))\GDI Objects" -EA 0).CounterSamples.CookedValue
                if ($gdiCount -gt 5000) {
                    Problem "GDI OBJECT LEAK: $($_.Name) has $gdiCount GDI objects - causes UI freezes"
                }
            } catch {}
        }
    } catch {}

    # Critical Services Not Responding
    $criticalSvcs = @('RpcSs', 'DcomLaunch', 'EventLog', 'ProfSvc', 'Schedule')
    foreach ($svcName in $criticalSvcs) {
        try {
            $svc = Get-Service -Name $svcName -EA 0
            if ($svc -and $svc.Status -ne 'Running') {
                CriticalProblem "CRITICAL SERVICE DOWN: $svcName - causes system instability/freezes"
            }
        } catch {}
    }

    # User Profile Service Issues (causes login freezes)
    try {
        Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-User Profiles Service'; Level=1,2,3; StartTime=$last7d} -EA 0 -MaxEvents 30 | ForEach-Object {
            CriticalProblem "USER PROFILE ERROR: $($_.Message.Substring(0,[Math]::Min(200,$_.Message.Length))))"
        }
    } catch {}

    # Shell Experience Host Crashes (causes Start Menu/Taskbar freeze)
    try {
        Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$bootTime} -EA 0 -MaxEvents 200 | Where-Object {
            $_.Message -match 'ShellExperienceHost.*crash|ShellExperienceHost.*terminated|StartMenuExperienceHost'
        } | ForEach-Object {
            Problem "SHELL UI CRASH: Start Menu/Taskbar component crashed at $($_.TimeCreated)"
        }
    } catch {}

    # Antivirus Real-Time Scan Causing Freezes
    try {
        $defenderStatus = Get-MpComputerStatus -EA 0
        if ($defenderStatus -and $defenderStatus.RealTimeProtectionEnabled) {
            # Check if causing high CPU
            $defenderProc = Get-Process -Name "MsMpEng" -EA 0
            if ($defenderProc -and $defenderProc.CPU -gt 20) {
                Problem "WINDOWS DEFENDER: Real-time scan using high CPU - causes freezes"
            }
        }
    } catch {}

    # NVME SSD Issues (specific to NVMe drives)
    Get-PhysicalDisk -EA 0 | Where-Object { $_.BusType -eq 'NVMe' } | ForEach-Object {
        try {
            # Check for errors
            $nvmeErrors = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$last7d} -EA 0 -MaxEvents 100 | Where-Object {
                $_.Message -match "$($_.FriendlyName)|NVMe" -and $_.Level -le 3
            }
            if ($nvmeErrors.Count -gt 5) {
                CriticalProblem "NVME ERRORS: $($_.FriendlyName) has $($nvmeErrors.Count) errors - causes freezes/data loss"
            }
        } catch {}
    }

} catch {
    Write-Host "  Error checking freeze/hang/crash detection: $_" -ForegroundColor DarkRed
}

# ============================================================================
# ADDITIONAL PERFORMANCE KILLERS
# ============================================================================
Section "MISC PERFORMANCE KILLERS"
Write-Host "Checking miscellaneous performance issues..." -ForegroundColor Magenta

try {
    # Startup Programs (slows boot & background performance)
    $startupProgs = Get-CimInstance Win32_StartupCommand -EA 0
    if ($startupProgs.Count -gt 20) {
        Problem "EXCESSIVE STARTUP PROGRAMS: $($startupProgs.Count) programs auto-start - slows boot/performance"
    }

    # Scheduled Tasks Running Frequently
    try {
        $tasks = Get-ScheduledTask -EA 0 | Where-Object { $_.State -eq 'Running' }
        if ($tasks.Count -gt 10) {
            Problem "MANY SCHEDULED TASKS: $($tasks.Count) tasks running - may impact performance"
        }
    } catch {}

    # Visual Effects (Aero, animations)
    $visualEffects = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -EA 0
    if ($visualEffects -and $visualEffects.VisualFXSetting -eq 0) {
        Problem "VISUAL EFFECTS: Set to 'Let Windows choose' - may use resources for animations"
    }

    # OneDrive Sync Overhead
    $oneDriveProc = Get-Process -Name "OneDrive" -EA 0
    if ($oneDriveProc) {
        try {
            $oneDriveCPU = $oneDriveProc.CPU
            if ($oneDriveCPU -gt 10) {
                Problem "ONEDRIVE: Actively syncing - using CPU/bandwidth in background"
            }
        } catch {}
    }

    # Windows Telemetry
    $telemetry = Get-Service -Name "DiagTrack" -EA 0
    if ($telemetry -and $telemetry.Status -eq 'Running') {
        Problem "TELEMETRY: DiagTrack service running - sends data in background"
    }

    # Font Cache Issues (can cause slowdowns)
    $fontCacheSize = (Get-ChildItem "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -EA 0 | Measure-Object -Property Length -Sum).Sum
    if ($fontCacheSize -gt 100MB) {
        Problem "FONT CACHE: $([math]::Round($fontCacheSize/1MB))MB - may be corrupted, causes slowdowns"
    }

    # Windows Update Pending
    try {
        $pendingUpdates = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates
        if ($pendingUpdates.Count -gt 0) {
            Problem "WINDOWS UPDATE: $($pendingUpdates.Count) updates pending - may install in background"
        }
    } catch {}

    # .NET Compilation Queue
    try {
        $ngenQueue = & "$env:windir\Microsoft.NET\Framework64\v4.0.30319\ngen.exe" queue status 2>$null
        if ($ngenQueue -match 'pending') {
            Problem ".NET NGEN: Assemblies pending compilation - background CPU usage"
        }
    } catch {}

    # Prefetch Folder Size (if too large, slows down)
    $prefetchSize = (Get-ChildItem "$env:windir\Prefetch" -EA 0 | Measure-Object -Property Length -Sum).Sum
    if ($prefetchSize -gt 50MB) {
        Problem "PREFETCH FOLDER: $([math]::Round($prefetchSize/1MB))MB - excessive, slows boot time"
    }

    # SoftwareDistribution (Windows Update cache)
    $swDistSize = (Get-ChildItem "$env:windir\SoftwareDistribution\Download" -Recurse -EA 0 | Measure-Object -Property Length -Sum).Sum
    if ($swDistSize -gt 500MB) {
        Problem "WINDOWS UPDATE CACHE: $([math]::Round($swDistSize/1MB))MB - can be cleaned"
    }

} catch {
    Write-Host "  Error checking misc performance: $_" -ForegroundColor DarkRed
}

Write-Host "`nULTIMATE PERFORMANCE DETECTION COMPLETE" -ForegroundColor Green

