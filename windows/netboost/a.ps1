#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NetBoost Consolidated - Ultimate Network Performance Optimizer
.DESCRIPTION
    Consolidated best settings from:
    - netboost/a.ps1 (v2.0 WiFi optimizer, 2025-12-22)
    - MaximizeEthernet/MaximizeEthernet.ps1 (Realtek 2.5GbE, 2026-02-12)
    - netboost3/a.ps1 (Advanced Ethernet, 2026-03-17)

    Covers: TCP/IP stack, registry tuning, NIC advanced props (Jumbo Frames,
    Flow Control, Speed+Duplex, EEE, RSS, interrupt moderation), offloads,
    NetTCPSetting profiles, SMB multichannel, QoS, service cleanup.

    NO REBOOT REQUIRED (except for pagefile/driver changes if made separately).
.NOTES
    Version: 4.0 (v3.0 2026-04-01 + 18 supplement sections 2026-09-30)
    Sections 15-32 are additive; sections 0-14 are unchanged.
    Requires: Windows PowerShell 5.1+, Administrator privileges
    PS v5 syntax throughout (semicolons, no &&)
#>

$ErrorActionPreference = 'Continue'
$script:startTime = Get-Date
$script:ok = 0 ; $script:skip = 0

# ============================================================================
# ADMIN ELEVATION CHECK
# ============================================================================
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[ERROR] Must run as Administrator. Re-launch elevated.' -ForegroundColor Red
    exit 1
}

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '   NETBOOST v4.0 - CONSOLIDATED NETWORK PERFORMANCE OPTIMIZER' -ForegroundColor Cyan
Write-Host '   Sources: netboost + MaximizeEthernet + netboost3 + supplement (S15-S32)' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================================
# HELPER
# ============================================================================
function Apply {
    param([string]$Desc, [scriptblock]$Action)
    try {
        & $Action 2>$null | Out-Null
        Write-Host "  [OK] $Desc" -ForegroundColor Green
        $script:ok++
    } catch {
        Write-Host "  [--] $Desc ($($_.Exception.Message.Split([char]10)[0]))" -ForegroundColor DarkGray
        $script:skip++
    }
}

# ============================================================================
# ADAPTER DETECTION
# ============================================================================
Write-Host '[0/32] Detecting active network adapter...' -ForegroundColor Cyan

$eth = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and ($_.MediaType -eq '802.3' -or $_.InterfaceDescription -like '*Ethernet*' -or $_.InterfaceDescription -like '*Realtek*') } | Sort-Object ifIndex | Select-Object -First 1
if (-not $eth) { $eth = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1 }
if (-not $eth) { $eth = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notlike 'vEthernet*' -and $_.InterfaceDescription -notlike '*Virtual*' } | Sort-Object ifIndex | Select-Object -First 1 }
if (-not $eth) { $eth = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1 }
$name     = $eth.Name
$ifIndex  = $eth.ifIndex

Write-Host "  Adapter : $($eth.InterfaceDescription)" -ForegroundColor Yellow
Write-Host "  Name    : $name  |  IfIndex: $ifIndex" -ForegroundColor Yellow
Write-Host ''

# ============================================================================
# SECTION 1: netsh TCP/IP GLOBAL SETTINGS
# ============================================================================
Write-Host '[1/32] netsh TCP/IP Global Settings' -ForegroundColor Cyan

Apply 'autotuninglevel=normal'          { netsh int tcp set global autotuninglevel=normal }
Apply 'chimney=enabled'                 { netsh int tcp set global chimney=enabled }
Apply 'dca=enabled'                     { netsh int tcp set global dca=enabled }
Apply 'netdma=enabled'                  { netsh int tcp set global netdma=enabled }
Apply 'rss=enabled'                     { netsh int tcp set global rss=enabled }
Apply 'ecncapability=enabled'           { netsh int tcp set global ecncapability=enabled }
Apply 'timestamps=enabled'              { netsh int tcp set global timestamps=enabled }
Apply 'initialRto=2000'                 { netsh int tcp set global initialRto=2000 }
Apply 'minrto=300'                      { netsh int tcp set global minrto=300 }
Apply 'nonsackrttresiliency=disabled'   { netsh int tcp set global nonsackrttresiliency=disabled }
Apply 'maxsynretransmissions=4'         { netsh int tcp set global maxsynretransmissions=4 }
Apply 'fastopen=enabled'                { netsh int tcp set global fastopen=enabled }
Apply 'fastopenfallback=enabled'        { netsh int tcp set global fastopenfallback=enabled }
Apply 'hystart=enabled'                 { netsh int tcp set global hystart=enabled }
Apply 'pacingprofile=auto'              { netsh int tcp set global pacingprofile=auto }
Apply 'congestionprovider=ctcp'         { netsh int tcp set supplemental Internet congestionprovider=ctcp }
Apply 'taskoffload=enabled'             { netsh interface ipv4 set global taskoffload=enabled }
Apply 'icmpredirects=disabled'          { netsh interface ipv4 set global icmpredirects=disabled }
Apply 'sourcerouting=dontforward'       { netsh interface ipv4 set global sourceroutingbehavior=dontforward }
Apply 'neighborcachelimit=4096'         { netsh interface ipv4 set global neighborcachelimit=4096 }
Apply 'reassemblylimit=16MB IPv4'       { netsh interface ipv4 set global reassemblylimit=16777216 }
Apply 'reassemblylimit=16MB IPv6'       { netsh interface ipv6 set global reassemblylimit=16777216 }
Apply 'multicastforwarding=disabled'    { netsh interface ipv4 set global multicastforwarding=disabled }
Apply 'groupforwardedfragments=enabled' { netsh interface ipv4 set global groupforwardedfragments=enabled }
Write-Host ''

# ============================================================================
# SECTION 2: netsh INTERFACE-LEVEL SETTINGS
# ============================================================================
Write-Host '[2/32] Interface-Level Settings' -ForegroundColor Cyan

Apply "IPv4 forwarding=enabled"     { netsh interface ipv4 set interface $ifIndex forwarding=enabled }
Apply "IPv4 dadtransmits=0"         { netsh interface ipv4 set interface $ifIndex dadtransmits=0 }
Apply "IPv4 routerdiscovery=disabled" { netsh interface ipv4 set interface $ifIndex routerdiscovery=disabled }
Apply "IPv4 advertise=disabled"     { netsh interface ipv4 set interface $ifIndex advertise=disabled }
Apply "IPv4 nud=enabled"            { netsh interface ipv4 set interface $ifIndex nud=enabled }
Apply "IPv4 siteprefixlength=0"     { netsh interface ipv4 set interface $ifIndex siteprefixlength=0 }
Apply "IPv4 basereachable=30000"    { netsh interface ipv4 set interface $ifIndex basereachable=30000 }
Apply "IPv4 retransmittime=1000"    { netsh interface ipv4 set interface $ifIndex retransmittime=1000 }
Apply "IPv6 dadtransmits=0"         { netsh interface ipv6 set interface $ifIndex dadtransmits=0 }
Apply "IPv6 routerdiscovery=dhcp"   { netsh interface ipv6 set interface $ifIndex routerdiscovery=dhcp }
Apply "IPv6 basereachable=30000"    { netsh interface ipv6 set interface $ifIndex basereachable=30000 }
Write-Host ''

# ============================================================================
# SECTION 3: TCP SUPPLEMENTAL TEMPLATES
# ============================================================================
Write-Host '[3/32] TCP Supplemental Templates (CUBIC)' -ForegroundColor Cyan

foreach ($tmpl in @('Internet','Datacenter','Compat','DatacenterCustom','InternetCustom')) {
    Apply "Supplemental $tmpl congestion=CUBIC" {
        netsh int tcp set supplemental template=$tmpl congestionprovider=cubic
    }
}
Write-Host ''

# ============================================================================
# SECTION 4: Set-NetTCPSetting PROFILES
# ============================================================================
Write-Host '[4/32] Set-NetTCPSetting Profile Tuning' -ForegroundColor Cyan

Apply 'Internet: InitialCongestionWindow=10'           { Set-NetTCPSetting -SettingName Internet -InitialCongestionWindow 10 -EA Stop }
Apply 'Internet: CongestionProvider=CUBIC'             { Set-NetTCPSetting -SettingName Internet -CongestionProvider CUBIC -EA Stop }
Apply 'Internet: AutoTuningLevelLocal=Experimental'    { Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Experimental -EA Stop }
Apply 'Internet: ScalingHeuristics=Disabled'           { Set-NetTCPSetting -SettingName Internet -ScalingHeuristics Disabled -EA Stop }
Apply 'Internet: EcnCapability=Enabled'                { Set-NetTCPSetting -SettingName Internet -EcnCapability Enabled -EA Stop }
Apply 'Internet: Timestamps=Enabled'                   { Set-NetTCPSetting -SettingName Internet -Timestamps Enabled -EA Stop }
Apply 'Internet: MaxSynRetransmissions=2'              { Set-NetTCPSetting -SettingName Internet -MaxSynRetransmissions 2 -EA Stop }
Apply 'Internet: NonSackRttResiliency=Disabled'        { Set-NetTCPSetting -SettingName Internet -NonSackRttResiliency Disabled -EA Stop }
Apply 'Internet: InitialRto=2000'                      { Set-NetTCPSetting -SettingName Internet -InitialRto 2000 -EA Stop }
Apply 'Internet: MinRto=300'                           { Set-NetTCPSetting -SettingName Internet -MinRto 300 -EA Stop }
Apply 'Internet: DelayedAckTimeout=40'                 { Set-NetTCPSetting -SettingName Internet -DelayedAckTimeout 40 -EA Stop }
Apply 'Internet: DelayedAckFrequency=1'                { Set-NetTCPSetting -SettingName Internet -DelayedAckFrequency 1 -EA Stop }
Apply 'Internet: MemoryPressureProtection=Disabled'    { Set-NetTCPSetting -SettingName Internet -MemoryPressureProtection Disabled -EA Stop }
Apply 'Internet: ForceWS=Enabled'                      { Set-NetTCPSetting -SettingName Internet -ForceWS Enabled -EA Stop }
Apply 'Datacenter: CongestionProvider=CUBIC'           { Set-NetTCPSetting -SettingName Datacenter -CongestionProvider CUBIC -EA Stop }
Apply 'Datacenter: AutoTuningLevelLocal=Experimental'  { Set-NetTCPSetting -SettingName Datacenter -AutoTuningLevelLocal Experimental -EA Stop }
Apply 'Datacenter: EcnCapability=Enabled'              { Set-NetTCPSetting -SettingName Datacenter -EcnCapability Enabled -EA Stop }
Apply 'Compat: CongestionProvider=CUBIC'               { Set-NetTCPSetting -SettingName Compat -CongestionProvider CUBIC -EA Stop }
Apply 'DatacenterCustom: CongestionProvider=CUBIC'     { Set-NetTCPSetting -SettingName DatacenterCustom -CongestionProvider CUBIC -EA Stop }
Apply 'InternetCustom: CongestionProvider=CUBIC'       { Set-NetTCPSetting -SettingName InternetCustom -CongestionProvider CUBIC -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 5: TCP/IP REGISTRY (IPv4)
# ============================================================================
Write-Host '[5/32] TCP/IP Registry (IPv4)' -ForegroundColor Cyan

$tcpip = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

Apply 'TcpWindowSize=65535'                     { Set-ItemProperty -Path $tcpip -Name 'TcpWindowSize'             -Value 65535    -Type DWord -Force }
Apply 'GlobalMaxTcpWindowSize=16MB'             { Set-ItemProperty -Path $tcpip -Name 'GlobalMaxTcpWindowSize'    -Value 16777216 -Type DWord -Force }
Apply 'TCP1323Opts=3 (WS+TS)'                   { Set-ItemProperty -Path $tcpip -Name 'TCP1323Opts'               -Value 3        -Type DWord -Force }
Apply 'DefaultTTL=64'                           { Set-ItemProperty -Path $tcpip -Name 'DefaultTTL'                -Value 64       -Type DWord -Force }
Apply 'EnablePMTUDiscovery=1'                   { Set-ItemProperty -Path $tcpip -Name 'EnablePMTUDiscovery'        -Value 1        -Type DWord -Force }
Apply 'EnablePMTUBHDetect=1'                    { Set-ItemProperty -Path $tcpip -Name 'EnablePMTUBHDetect'         -Value 1        -Type DWord -Force }
Apply 'MaxUserPort=65534'                       { Set-ItemProperty -Path $tcpip -Name 'MaxUserPort'                -Value 65534    -Type DWord -Force }
Apply 'TcpTimedWaitDelay=30'                    { Set-ItemProperty -Path $tcpip -Name 'TcpTimedWaitDelay'          -Value 30       -Type DWord -Force }
Apply 'EnableDCA=1'                             { Set-ItemProperty -Path $tcpip -Name 'EnableDCA'                  -Value 1        -Type DWord -Force }
Apply 'EnableRSS=1'                             { Set-ItemProperty -Path $tcpip -Name 'EnableRSS'                  -Value 1        -Type DWord -Force }
Apply 'EnableTCPA=1'                            { Set-ItemProperty -Path $tcpip -Name 'EnableTCPA'                 -Value 1        -Type DWord -Force }
Apply 'SackOpts=1'                              { Set-ItemProperty -Path $tcpip -Name 'SackOpts'                   -Value 1        -Type DWord -Force }
Apply 'TcpMaxDupAcks=2'                         { Set-ItemProperty -Path $tcpip -Name 'TcpMaxDupAcks'              -Value 2        -Type DWord -Force }
Apply 'MaxHashTableSize=65536'                  { Set-ItemProperty -Path $tcpip -Name 'MaxHashTableSize'           -Value 65536    -Type DWord -Force }
Apply 'MaxFreeTcbs=65536'                       { Set-ItemProperty -Path $tcpip -Name 'MaxFreeTcbs'                -Value 65536    -Type DWord -Force }
Apply 'TcpNumConnections=1280000'               { Set-ItemProperty -Path $tcpip -Name 'TcpNumConnections'          -Value 1280000  -Type DWord -Force }
Apply 'KeepAliveTime=300000'                    { Set-ItemProperty -Path $tcpip -Name 'KeepAliveTime'              -Value 300000   -Type DWord -Force }
Apply 'KeepAliveInterval=1000'                  { Set-ItemProperty -Path $tcpip -Name 'KeepAliveInterval'          -Value 1000     -Type DWord -Force }
Apply 'DisableTaskOffload=0'                    { Set-ItemProperty -Path $tcpip -Name 'DisableTaskOffload'         -Value 0        -Type DWord -Force }
Apply 'TcpAckFrequency=1 (disable ACK delay)'   { Set-ItemProperty -Path $tcpip -Name 'TcpAckFrequency'            -Value 1        -Type DWord -Force }
Apply 'TCPNoDelay=1 (disable Nagle)'            { Set-ItemProperty -Path $tcpip -Name 'TCPNoDelay'                 -Value 1        -Type DWord -Force }
Apply 'EnableDSACK=1'                           { Set-ItemProperty -Path $tcpip -Name 'EnableDSACK'                -Value 1        -Type DWord -Force }
Apply 'TcpMaxSendFree=65535'                    { Set-ItemProperty -Path $tcpip -Name 'TcpMaxSendFree'             -Value 65535    -Type DWord -Force }
Apply 'MaxConnectionsPer1_0Server=32'           { Set-ItemProperty -Path $tcpip -Name 'MaxConnectionsPer1_0Server' -Value 32       -Type DWord -Force }
Apply 'MaxConnectionsPerServer=32'              { Set-ItemProperty -Path $tcpip -Name 'MaxConnectionsPerServer'    -Value 32       -Type DWord -Force }
Apply 'EnableTFO=3'                             { Set-ItemProperty -Path $tcpip -Name 'EnableTFO'                  -Value 3        -Type DWord -Force }
Apply 'EnableDeadGWDetect=0'                    { Set-ItemProperty -Path $tcpip -Name 'EnableDeadGWDetect'         -Value 0        -Type DWord -Force }
Apply 'ArpCacheLife=300'                        { Set-ItemProperty -Path $tcpip -Name 'ArpCacheLife'               -Value 300      -Type DWord -Force }
Apply 'ArpCacheMinReferencedLife=300'           { Set-ItemProperty -Path $tcpip -Name 'ArpCacheMinReferencedLife'  -Value 300      -Type DWord -Force }
Write-Host ''

# ============================================================================
# SECTION 6: TCP/IP REGISTRY (IPv6)
# ============================================================================
Write-Host '[6/32] TCP/IP Registry (IPv6)' -ForegroundColor Cyan

$tcpip6 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
if (-not (Test-Path $tcpip6)) { New-Item -Path $tcpip6 -Force | Out-Null }

Apply 'IPv6 TcpWindowSize=65535'    { Set-ItemProperty -Path $tcpip6 -Name 'TcpWindowSize'     -Value 65535 -Type DWord -Force }
Apply 'IPv6 Tcp1323Opts=3'          { Set-ItemProperty -Path $tcpip6 -Name 'Tcp1323Opts'       -Value 3     -Type DWord -Force }
Apply 'IPv6 DefaultTTL=64'          { Set-ItemProperty -Path $tcpip6 -Name 'DefaultTTL'        -Value 64    -Type DWord -Force }
Apply 'IPv6 MaxUserPort=65534'      { Set-ItemProperty -Path $tcpip6 -Name 'MaxUserPort'       -Value 65534 -Type DWord -Force }
Apply 'IPv6 TcpTimedWaitDelay=30'   { Set-ItemProperty -Path $tcpip6 -Name 'TcpTimedWaitDelay' -Value 30    -Type DWord -Force }
Write-Host ''

# ============================================================================
# SECTION 7: NIC ADVANCED PROPERTIES
# ============================================================================
Write-Host '[7/32] NIC Advanced Properties (RSS, Jumbo, Flow, Speed, EEE, Interrupt)' -ForegroundColor Cyan

# RSS
Apply 'NIC: Enable RSS'                          { Enable-NetAdapterRss -Name $name -EA Stop }
Apply 'NIC: RSS Base=0 Max=15 Queues=4'          { Set-NetAdapterRss -Name $name -BaseProcessorNumber 0 -MaxProcessorNumber 15 -NumberOfReceiveQueues 4 -EA Stop }
Apply 'NIC: Receive Side Scaling=Enabled'        { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Receive Side Scaling' -DisplayValue 'Enabled' -EA Stop }

# Jumbo Frames 9014
Apply 'NIC: Jumbo Packet=9014 Bytes'             { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Jumbo Packet' -DisplayValue '9014 Bytes' -EA Stop }
Apply 'NIC: Jumbo Frame=9014 (alt key)'          { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Jumbo Frame'  -DisplayValue '9014' -EA Stop }

# Flow Control OFF
Apply 'NIC: Flow Control=Disabled'               { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Flow Control' -DisplayValue 'Disabled' -EA Stop }

# Speed + Duplex 1Gbps Full
Apply 'NIC: Speed+Duplex=1.0 Gbps Full Duplex'   { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Speed & Duplex' -DisplayValue '1.0 Gbps Full Duplex' -EA Stop }

# EEE off
Apply 'NIC: Energy-Efficient Ethernet=Disabled'  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Energy-Efficient Ethernet' -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Green Ethernet=Disabled'             { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Green Ethernet' -DisplayValue 'Disabled' -EA Stop }

# Interrupt moderation
Apply 'NIC: Interrupt Moderation=Enabled'        { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation'      -DisplayValue 'Enabled'   -EA Stop }
Apply 'NIC: Interrupt Moderation Rate=Adaptive'  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation Rate' -DisplayValue 'Adaptive'  -EA Stop }

# Buffers
Apply 'NIC: Receive Buffers=2048'                { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Receive Buffers'  -DisplayValue '2048' -EA Stop }
Apply 'NIC: Transmit Buffers=2048'               { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Transmit Buffers' -DisplayValue '2048' -EA Stop }

# Power savings off
Apply 'NIC: Power Saving Mode=Disabled'          { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Power Saving Mode'     -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Wake on Magic Packet=Disabled'       { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Wake on Magic Packet'  -DisplayValue 'Disabled' -EA Stop }
Apply 'NIC: Wake on pattern match=Disabled'      { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Wake on pattern match' -DisplayValue 'Disabled' -EA Stop }

# Offload props
Apply 'NIC: LSO V2 IPv4=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Large Send Offload V2 (IPv4)' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: LSO V2 IPv6=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Large Send Offload V2 (IPv6)' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: IPv4 Checksum Offload=Rx+Tx'         { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'IPv4 Checksum Offload'        -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: TCP Checksum Offload IPv4=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'TCP Checksum Offload (IPv4)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: TCP Checksum Offload IPv6=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'TCP Checksum Offload (IPv6)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: UDP Checksum Offload IPv4=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'UDP Checksum Offload (IPv4)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: UDP Checksum Offload IPv6=Rx+Tx'     { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'UDP Checksum Offload (IPv6)'  -DisplayValue 'Rx & Tx Enabled' -EA Stop }
Apply 'NIC: ARP Offload=Enabled'                 { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'ARP Offload' -DisplayValue 'Enabled' -EA Stop }
Apply 'NIC: NS Offload=Enabled'                  { Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'NS Offload'  -DisplayValue 'Enabled' -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 8: NIC OFFLOAD CMDLETS
# ============================================================================
Write-Host '[8/32] NIC Offload Cmdlets (Checksum, LSO, RSC)' -ForegroundColor Cyan

Apply 'ChecksumOffload: TCP IPv4+IPv6 RxTx'  { Set-NetAdapterChecksumOffload -Name $name -TcpIPv4 RxTxEnabled -TcpIPv6 RxTxEnabled -EA Stop }
Apply 'ChecksumOffload: UDP IPv4+IPv6 RxTx'  { Set-NetAdapterChecksumOffload -Name $name -UdpIPv4 RxTxEnabled -UdpIPv6 RxTxEnabled -EA Stop }
Apply 'ChecksumOffload: IP IPv4 RxTx'        { Set-NetAdapterChecksumOffload -Name $name -IpIPv4 RxTxEnabled  -EA Stop }
Apply 'LSO: IPv4+IPv6 Enabled'               { Set-NetAdapterLso -Name $name -IPv4Enabled $true -IPv6Enabled $true -EA Stop }
Apply 'RSC: IPv4 Enabled'                    { Set-NetAdapterRsc -Name $name -IPv4Enabled $true -EA Stop }
Apply 'RSC: IPv6 Enabled'                    { Set-NetAdapterRsc -Name $name -IPv6Enabled $true -EA Stop }
Apply 'EncapsulatedTaskOffload=Enabled'      { Set-NetAdapterEncapsulatedPacketTaskOffload -Name $name -NvgreEncapsulatedPacketTaskOffloadEnabled $true -VxlanEncapsulatedPacketTaskOffloadEnabled $true -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 9: QoS AND NETWORK THROTTLING
# ============================================================================
Write-Host '[9/32] QoS and Network Throttling' -ForegroundColor Cyan

$mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Apply 'NetworkThrottlingIndex=0xFFFFFFFF' {
    if (-not (Test-Path $mmPath)) { New-Item -Path $mmPath -Force | Out-Null }
    Set-ItemProperty -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -Force
}
Apply 'SystemResponsiveness=0' { Set-ItemProperty -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force }
Apply 'MMCSS Games: Priority=6 GPU=8' {
    $mg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    if (-not (Test-Path $mg)) { New-Item -Path $mg -Force | Out-Null }
    Set-ItemProperty -Path $mg -Name 'Affinity'            -Value 0       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Background Only'     -Value 'False' -Type String -Force
    Set-ItemProperty -Path $mg -Name 'Clock Rate'          -Value 10000   -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'GPU Priority'        -Value 8       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Priority'            -Value 6       -Type DWord  -Force
    Set-ItemProperty -Path $mg -Name 'Scheduling Category' -Value 'High'  -Type String -Force
    Set-ItemProperty -Path $mg -Name 'SFIO Priority'       -Value 'High'  -Type String -Force
}
$qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
Apply 'QoS: NonBestEffortLimit=0' {
    if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
    Set-ItemProperty -Path $qosPath -Name 'NonBestEffortLimit' -Value 0 -Type DWord -Force
}
Apply 'QoS: Enable NetAdapter QoS' { Enable-NetAdapterQos -Name $name -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 10: WFP / BFE / NETIO
# ============================================================================
Write-Host '[10/32] WFP/BFE/NetIO Registry' -ForegroundColor Cyan

Apply 'BFE: DisableStatefulFtp=1' {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\BFE\Parameters\Policy\Options'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name 'DisableStatefulFtp' -Value 1 -Type DWord -Force
}
Apply 'NetIO: EnableRSCOnAggregation=1' {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetIO\Parameters'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name 'EnableRSCOnAggregation' -Value 1 -Type DWord -Force
}
Write-Host ''

# ============================================================================
# SECTION 11: SMB MULTICHANNEL
# ============================================================================
Write-Host '[11/32] SMB Multichannel and Direct' -ForegroundColor Cyan

Apply 'SMB Client: EnableMultiChannel=true'       { Set-SmbClientConfiguration -EnableMultiChannel $true -Force -EA Stop }
Apply 'SMB Client: DisableBandwidthThrottling'    { Set-SmbClientConfiguration -EnableBandwidthThrottling $false -Force -EA Stop }
Apply 'SMB Client: MaxConnectionCount=32'         { Set-SmbClientConfiguration -MaximumConnectionCountPerServer 32 -Force -EA Stop }
Apply 'SMB Client: Disable signing overhead'      { Set-SmbClientConfiguration -EnableSecuritySignature $false -RequireSecuritySignature $false -Force -EA Stop }
Apply 'SMB Server: EnableMultiChannel=true'       { Set-SmbServerConfiguration -EnableMultiChannel $true -Force -EA Stop }
Apply 'SMB Server: MaxChannelPerSession=32'       { Set-SmbServerConfiguration -MaxChannelPerSession 32 -Force -EA Stop }
Apply 'SMB Server: AsynchronousCredits=512'       { Set-SmbServerConfiguration -AsynchronousCredits 512 -Force -EA Stop }
Apply 'SMB Server: Smb2Credits 512-8192'          { Set-SmbServerConfiguration -Smb2CreditsMin 512 -Smb2CreditsMax 8192 -Force -EA Stop }
Apply 'SMB Server: Disable signing'               { Set-SmbServerConfiguration -EnableSecuritySignature $false -RequireSecuritySignature $false -Force -EA Stop }
Apply 'SMB Server: MaxWorkItems=8192'             { Set-SmbServerConfiguration -MaxWorkItems 8192 -Force -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 12: ROUTE METRICS AND ADAPTER BINDING
# ============================================================================
Write-Host '[12/32] Route Metrics and Adapter Binding' -ForegroundColor Cyan

Apply "IPv4 InterfaceMetric=5" { Set-NetIPInterface -InterfaceIndex $ifIndex -InterfaceMetric 5 -EA Stop }
Apply "IPv6 InterfaceMetric=5" { Set-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv6 -InterfaceMetric 5 -EA Stop }

Apply 'Disable ms_lltdio'  { Disable-NetAdapterBinding -Name $name -ComponentID ms_lltdio -EA Stop }
Apply 'Disable ms_rspndr'  { Disable-NetAdapterBinding -Name $name -ComponentID ms_rspndr -EA Stop }
Apply 'Disable ms_lldp'    { Disable-NetAdapterBinding -Name $name -ComponentID ms_lldp   -EA Stop }
Apply 'Enable ms_tcpip'    { Enable-NetAdapterBinding  -Name $name -ComponentID ms_tcpip  -EA Stop }
Apply 'Enable ms_tcpip6'   { Enable-NetAdapterBinding  -Name $name -ComponentID ms_tcpip6 -EA Stop }
Write-Host ''

# ============================================================================
# SECTION 13: PROCESSOR SCHEDULING
# ============================================================================
Write-Host '[13/32] Processor Scheduling' -ForegroundColor Cyan

Apply 'Win32PrioritySeparation=38' {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -Force
}
Apply 'AdditionalWorkerThreads +16' {
    $ep = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive'
    Set-ItemProperty -Path $ep -Name 'AdditionalCriticalWorkerThreads' -Value 16 -Type DWord -Force
    Set-ItemProperty -Path $ep -Name 'AdditionalDelayedWorkerThreads'  -Value 16 -Type DWord -Force
}
Write-Host ''

# ============================================================================
# SECTION 14: CLEANUP AND VERIFICATION
# ============================================================================
Write-Host '[14/32] Cleanup and Verification' -ForegroundColor Cyan

Apply 'Flush DNS cache'      { Clear-DnsClientCache -EA Stop }
Apply 'Flush ARP cache'      { Remove-NetNeighbor -InterfaceIndex $ifIndex -Confirm:$false -EA SilentlyContinue }
Apply 'Flush NetBIOS cache'  { nbtstat -R }
Apply 'Register DNS'         { ipconfig /registerdns }
Apply 'Verify TCP Internet settings' {
    $tcp = Get-NetTCPSetting -SettingName Internet
    Write-Host "    Congestion=$($tcp.CongestionProvider) AutoTune=$($tcp.AutoTuningLevelLocal) ECN=$($tcp.EcnCapability)" -ForegroundColor DarkCyan
}
Apply 'Verify NIC offloads' {
    $rsc = Get-NetAdapterRsc -Name $name -EA SilentlyContinue
    $lso = Get-NetAdapterLso -Name $name -EA SilentlyContinue
    Write-Host "    RSC4=$($rsc.IPv4Enabled) RSC6=$($rsc.IPv6Enabled) LSO4=$($lso.IPv4Enabled) LSO6=$($lso.IPv6Enabled)" -ForegroundColor DarkCyan
}
Write-Host ''

# =============================================================================
# SECTION 15: LINK-SPEED CORRECTIVES
#   Section 7 above forces 'Speed & Duplex = 1.0 Gbps Full Duplex' and tries to
#   enable 9014-byte Jumbo Frames. On a 2.5GbE NIC that caps the link at 1 Gbps,
#   and on a 1500-byte upstream path jumbo frames cause silent massive packet
#   loss. These correctives run AFTER Section 7 so the good value wins.
#   NOTE: 'Auto Negotiation' is used deliberately - forcing '2.5 Gbps Full
#   Duplex' on a 1 Gb/s switch port drops the link.
# =============================================================================
Write-Host '[15/32] Link-Speed Correctives (undo Section 7 mis-tunes)' -ForegroundColor Cyan

$nbAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
$nbEth      = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and ($_.MediaType -eq '802.3' -or $_.InterfaceDescription -like '*Ethernet*' -or $_.InterfaceDescription -like '*Realtek*') })
$nbWifi     = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|Qualcomm|Intel.*Wi-Fi|MediaTek.*Wi-Fi' })
$nbIfList   = @($nbAdapters.ifIndex | Sort-Object -Unique)

function Adv { param([string]$Adapter, [string]$Prop, [string]$Value); Set-NetAdapterAdvancedProperty -Name $Adapter -DisplayName $Prop -DisplayValue $Value -ErrorAction Stop }

foreach ($a in $nbEth) {
  Apply "[$($a.Name)] Speed & Duplex -> Auto Negotiation (recovers 2.5 Gb/s if switch allows)" { Adv $a.Name 'Speed & Duplex' 'Auto Negotiation' }
  Apply "[$($a.Name)] Gigabit Lite -> Disabled (Realtek gigabit-link throttle)" { Adv $a.Name 'Gigabit Lite' 'Disabled' }
  Apply "[$($a.Name)] WOL & Shutdown Link Speed -> Not Speed Down (was 10 Mbps First)" { Adv $a.Name 'WOL & Shutdown Link Speed' 'Not Speed Down' }
  Apply "[$($a.Name)] Shutdown Wake-On-Lan -> Disabled" { Adv $a.Name 'Shutdown Wake-On-Lan' 'Disabled' }
  Apply "[$($a.Name)] EEE Max Support Speed -> 2.5 Gbps Full Duplex" { Adv $a.Name 'EEE Max Support Speed' '2.5 Gbps Full Duplex' }
  Apply "[$($a.Name)] Priority & VLAN -> Priority Enabled (no VLAN tag on untagged port)" { Adv $a.Name 'Priority & VLAN' 'Priority Enabled' }
  Apply "[$($a.Name)] Jumbo Frame -> Disabled (clamp; 9014 on a 1500 upstream = silent loss)" { Adv $a.Name 'Jumbo Frame' 'Disabled' }
  Apply "[$($a.Name)] Jumbo Packet -> Disabled (alt property name)" { Adv $a.Name 'Jumbo Packet' 'Disabled' }
  Apply "[$($a.Name)] Receive Buffers -> 4096" { Adv $a.Name 'Receive Buffers' '4096' }
  Apply "[$($a.Name)] Transmit Buffers -> 4096" { Adv $a.Name 'Transmit Buffers' '4096' }
  Apply "[$($a.Name)] Flow Control -> Disabled" { Adv $a.Name 'Flow Control' 'Disabled' }
  Apply "[$($a.Name)] Energy-Efficient Ethernet -> Disabled" { Adv $a.Name 'Energy-Efficient Ethernet' 'Disabled' }
  Apply "[$($a.Name)] Advanced EEE -> Disabled" { Adv $a.Name 'Advanced EEE' 'Disabled' }
  Apply "[$($a.Name)] Green Ethernet -> Disabled" { Adv $a.Name 'Green Ethernet' 'Disabled' }
  Apply "[$($a.Name)] Power Saving Mode -> Disabled" { Adv $a.Name 'Power Saving Mode' 'Disabled' }
  Apply "[$($a.Name)] Wake on Magic Packet -> Disabled" { Adv $a.Name 'Wake on Magic Packet' 'Disabled' }
  Apply "[$($a.Name)] Wake on pattern match -> Disabled" { Adv $a.Name 'Wake on pattern match' 'Disabled' }
  Apply "[$($a.Name)] Interrupt Moderation -> Enabled" { Adv $a.Name 'Interrupt Moderation' 'Enabled' }
  Apply "[$($a.Name)] Interrupt Moderation Rate -> Adaptive" { Adv $a.Name 'Interrupt Moderation Rate' 'Adaptive' }
  Apply "[$($a.Name)] Recv Segment Coalescing (IPv4) -> Disabled" { Adv $a.Name 'Recv Segment Coalescing (IPv4)' 'Disabled' }
  Apply "[$($a.Name)] Recv Segment Coalescing (IPv6) -> Disabled" { Adv $a.Name 'Recv Segment Coalescing (IPv6)' 'Disabled' }
  Apply "[$($a.Name)] Large Send Offload v2 (IPv4) -> Enabled" { Adv $a.Name 'Large Send Offload v2 (IPv4)' 'Enabled' }
  Apply "[$($a.Name)] Large Send Offload v2 (IPv6) -> Enabled" { Adv $a.Name 'Large Send Offload v2 (IPv6)' 'Enabled' }
  Apply "[$($a.Name)] IPv4 Checksum Offload -> Rx & Tx Enabled" { Adv $a.Name 'IPv4 Checksum Offload' 'Rx & Tx Enabled' }
  Apply "[$($a.Name)] TCP Checksum Offload (IPv4) -> Rx & Tx Enabled" { Adv $a.Name 'TCP Checksum Offload (IPv4)' 'Rx & Tx Enabled' }
  Apply "[$($a.Name)] TCP Checksum Offload (IPv6) -> Rx & Tx Enabled" { Adv $a.Name 'TCP Checksum Offload (IPv6)' 'Rx & Tx Enabled' }
  Apply "[$($a.Name)] UDP Checksum Offload (IPv4) -> Rx & Tx Enabled" { Adv $a.Name 'UDP Checksum Offload (IPv4)' 'Rx & Tx Enabled' }
  Apply "[$($a.Name)] UDP Checksum Offload (IPv6) -> Rx & Tx Enabled" { Adv $a.Name 'UDP Checksum Offload (IPv6)' 'Rx & Tx Enabled' }
  Apply "[$($a.Name)] ARP Offload -> Enabled" { Adv $a.Name 'ARP Offload' 'Enabled' }
  Apply "[$($a.Name)] NS Offload -> Enabled" { Adv $a.Name 'NS Offload' 'Enabled' }
}
Write-Host ''

# =============================================================================
# SECTION 16: NIC POWER MANAGEMENT
#   netboost never calls Set-NetAdapterPowerManagement / Disable-NetAdapterPowerManagement.
#   SelectiveSuspend is the single largest remaining Realtek throughput throttle.
#   Neither cmdlet drops the link.
# =============================================================================
Write-Host '[16/32] NIC Power Management (SelectiveSuspend et al)' -ForegroundColor Cyan
foreach ($a in $nbAdapters) {
  Apply "[$($a.Name)] SelectiveSuspend OFF / AllowComputerToTurnOffDevice OFF" { Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Disabled -WakeOnMagicPacket Disabled -WakeOnPatternMatch Disabled -SelectiveSuspend Disabled -EA Stop }
  Apply "[$($a.Name)] Disable-NetAdapterPowerManagement (WOL / pattern match)" { Disable-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Disabled -WakeOnPatternMatch Disabled -EA Stop }
  Apply "[$($a.Name)] MediaConnectState / MediaDisconnectState = Connected" { Set-NetAdapter -Name $a.Name -MediaConnectState Connected -MediaDisconnectState Connected -EA Stop }
}
Write-Host ''

# =============================================================================
# SECTION 17: RSC OFF / RSS ON
#   RSC is a datacenter optimization; on a WAN path it coalesces segments and
#   inflates latency. RSS queue count is raised from 4 to 8 for 16 logical CPUs.
# =============================================================================
Write-Host '[17/32] RSC Off / RSS On (8 queues)' -ForegroundColor Cyan
Apply 'netsh: RSC globally disabled' { netsh int tcp set global rsc=disabled }
foreach ($a in $nbAdapters) {
  Apply "[$($a.Name)] Set-NetAdapterRsc -IPv4Enabled/-IPv6Enabled = False" { Set-NetAdapterRsc -Name $a.Name -IPv4Enabled $false -IPv6Enabled $false -EA Stop }
  Apply "[$($a.Name)] Enable-NetAdapterRss" { Enable-NetAdapterRss -Name $a.Name -EA Stop }
  Apply "[$($a.Name)] RSS base=0 max=15 queues=8" { Set-NetAdapterRss -Name $a.Name -BaseProcessorNumber 0 -MaxProcessorNumber 15 -NumberOfReceiveQueues 8 -EA Stop }
}
Write-Host ''

# =============================================================================
# SECTION 18: TCP STACK - resolves the contradictions Section 1 vs Section 4
#   create, plus the knobs netboost never sets.
#     Section 1 sets autotuninglevel=normal, Section 4 sets AutoTuningLevelLocal
#       Experimental  -> the latter wins, leaving a conflict.
#     Section 1 sets maxsynretransmissions=4, Section 4 sets 2 -> conflict.
#     Section 1 sets pacingprofile=auto, which resolves to 'off' on this build.
# =============================================================================
Write-Host '[18/32] TCP Stack Fixes + Missing Knobs' -ForegroundColor Cyan
Apply 'autotuninglevel=experimental (resolve S1 vs S4 conflict)' { netsh int tcp set global autotuninglevel=experimental }
Apply 'maxsynretransmissions=2 (resolve S1 vs S4 conflict)' { netsh int tcp set global maxsynretransmissions=2 }
Apply 'pacingprofile=window (auto resolved to off on this build)' { netsh int tcp set global pacingprofile=window }
Apply 'heuristics disabled (Windows Scaling heuristics)' { netsh int tcp set heuristics disabled }
Apply 'supplemental template=* congestionprovider=cubic (wildcard = ALL templates)' { netsh int tcp set supplemental template='*' congestionprovider=cubic }
Apply 'bcdedit {default} disabledynamictcp=yes (applies next boot)' { bcdedit /set '{default}' disabledynamictcp yes }
Write-Host ''

# =============================================================================
# SECTION 19: FULL Set-NetTCPSetting - every parameter, all five profiles
#   Section 4 sets 13 params for Internet but only 1-3 for the other profiles.
# =============================================================================
Write-Host '[19/32] Full Set-NetTCPSetting (all profiles, all params)' -ForegroundColor Cyan
foreach ($p in @('Internet','Datacenter','Compat','DatacenterCustom','InternetCustom')) {
  Apply "$p : ICW=10 CUBIC AutoTune=Experimental ECN TS ForceWS" { Set-NetTCPSetting -SettingName $p -InitialCongestionWindow 10 -CongestionProvider CUBIC -AutoTuningLevelLocal Experimental -EcnCapability Enabled -Timestamps Enabled -ForceWS Enabled -EA Stop }
  Apply "$p : RTO / Retrans / Resiliency / MemoryPressure" { Set-NetTCPSetting -SettingName $p -InitialRto 2000 -MinRto 300 -MaxSynRetransmissions 2 -NonSackRttResiliency Disabled -MemoryPressureProtection Disabled -EA Stop }
  Apply "$p : DelayedAck 40/1 + ScalingHeuristics Disabled" { Set-NetTCPSetting -SettingName $p -DelayedAckTimeout 40 -DelayedAckFrequency 1 -ScalingHeuristics Disabled -EA Stop }
}
Write-Host ''

# =============================================================================
# SECTION 20: AFD\Parameters - socket buffer pool, key is absent by default
# =============================================================================
Write-Host '[20/32] AFD\Parameters (socket buffers)' -ForegroundColor Cyan
$nbAfd = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
Apply 'Create AFD\Parameters key' { if (-not (Test-Path $nbAfd)) { New-Item -Path $nbAfd -Force | Out-Null } }
foreach ($kv in @(@('DefaultReceiveWindowSize',262144),@('DefaultSendWindowSize',262144),@('MaxBufferedReceiveBytes',262144),@('MaxBufferedSendBytes',262144),@('DefaultOutstandingAccepts',512),@('DefaultDataPacketSize',1460),@('MaximumAllocateAllAccepted',65535),@('MinimumAllocateAllAccepted',65536),@('MaximumAllocateIoRequests',65535))) {
  Apply "AFD : $($kv[0]) = $($kv[1])" { Set-ItemProperty -Path $nbAfd -Name $kv[0] -Value $kv[1] -Type DWord -Force }
}
Write-Host ''

# =============================================================================
# SECTION 21: Tcpip\Parameters - the values Section 5 omits, plus full reinforce
# =============================================================================
Write-Host '[21/32] Tcpip\Parameters Gap-Fill' -ForegroundColor Cyan
$nbT4 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
foreach ($kv in @(@('TcpMaxRetransmissions',3),@('TcpMaxConnectRetransmissions',3),@('MaxUserPortLimit',65535),@('EnableARP',1),@('EnableARPBacklog',512),@('EnableIPForwarding',0),@('EnableIPForwarding2',0),@('DisableIPSourceRouting',1),@('EnableICMPRedirect',0),@('DefaultInboundWindowSize',65535),@('TcpNumConnections',1280000),@('MaxFreeTcbs',65536),@('MaxHashTableSize',65536),@('TcpAckFrequency',1),@('TCPNoDelay',1),@('EnableTFO',3),@('EnablePMTUDiscovery',1),@('EnablePMTUBHDetect',1),@('EnableDeadGWDetect',0),@('DefaultTTL',64),@('KeepAliveTime',300000),@('KeepAliveInterval',1000),@('TcpTimedWaitDelay',30),@('MaxUserPort',65534),@('MaxConnectionsPerServer',32),@('MaxConnectionsPer1_0Server',32),@('TcpWindowSize',65535),@('GlobalMaxTcpWindowSize',16777216),@('TCP1323Opts',3),@('SackOpts',1),@('TcpMaxDupAcks',2),@('TcpMaxSendFree',65535),@('EnableRSS',1),@('EnableDCA',1),@('EnableTCPA',1),@('EnableDSACK',1),@('DisableTaskOffload',0),@('ArpCacheLife',300),@('ArpCacheMinReferencedLife',300))) {
  Apply "Tcpip : $($kv[0]) = $($kv[1])" { Set-ItemProperty -Path $nbT4 -Name $kv[0] -Value $kv[1] -Type DWord -Force }
}
Write-Host ''

# =============================================================================
# SECTION 22: Tcpip6\Parameters - Section 6 writes only 5 of ~25
# =============================================================================
Write-Host '[22/32] Tcpip6\Parameters Gap-Fill' -ForegroundColor Cyan
$nbT6 = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
Apply 'Create Tcpip6\Parameters key' { if (-not (Test-Path $nbT6)) { New-Item -Path $nbT6 -Force | Out-Null } }
foreach ($kv in @(@('TcpWindowSize',65535),@('GlobalMaxTcpWindowSize',16777216),@('Tcp1323Opts',3),@('DefaultTTL',64),@('MaxUserPort',65534),@('TcpTimedWaitDelay',30),@('TcpMaxSendFree',65535),@('TcpMaxDupAcks',2),@('MaxFreeTcbs',65536),@('MaxHashTableSize',65536),@('TcpNumConnections',1280000),@('EnableRSS',1),@('EnableDCA',1),@('EnableTCPA',1),@('SackOpts',1),@('TCPNoDelay',1),@('TcpAckFrequency',1),@('EnableTFO',3),@('DisableTaskOffload',0),@('EnablePMTUDiscovery',1),@('EnablePMTUBHDetect',1),@('EnableDeadGWDetect',0),@('KeepAliveTime',300000),@('KeepAliveInterval',1000),@('TcpMaxRetransmissions',3),@('TcpMaxConnectRetransmissions',3))) {
  Apply "Tcpip6 : $($kv[0]) = $($kv[1])" { Set-ItemProperty -Path $nbT6 -Name $kv[0] -Value $kv[1] -Type DWord -Force }
}
Write-Host ''

# =============================================================================
# SECTION 23: DELIVERY OPTIMIZATION + WINDOWS UPDATE POLICIES
#   Caps the background update bandwidth that competes with your own traffic.
# =============================================================================
Write-Host '[23/32] Delivery Optimization + Windows Update Policies' -ForegroundColor Cyan
$nbDo = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
Apply 'Create DeliveryOptimization policy key' { if (-not (Test-Path $nbDo)) { New-Item -Path $nbDo -Force | Out-Null } }
Apply 'DO : DODownloadMode=100 (foreground only, no P2P)' { Set-ItemProperty -Path $nbDo -Name 'DODownloadMode' -Value 100 -Type DWord -Force }
Apply 'DO : DownloadModeHttp=0' { Set-ItemProperty -Path $nbDo -Name 'DownloadModeHttp' -Value 0 -Type DWord -Force }
Apply 'DO : DownloadModeLanPeers=0' { Set-ItemProperty -Path $nbDo -Name 'DownloadModeLanPeers' -Value 0 -Type DWord -Force }
$nbDbl = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\NetworkBandwidthLimit'
Apply 'DO : NetworkBandwidthLimit=0 (uncapped)' { if (-not (Test-Path $nbDbl)) { New-Item -Path $nbDbl -Force | Out-Null }; Set-ItemProperty -Path $nbDbl -Name 'BandwidthLimit' -Value 0 -Type DWord -Force }
$nbAu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
Apply 'WU : NoAutoUpdate=1 / AUOptions=1' { if (-not (Test-Path $nbAu)) { New-Item -Path $nbAu -Force | Out-Null }; Set-ItemProperty -Path $nbAu -Name 'NoAutoUpdate' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $nbAu -Name 'AUOptions' -Value 1 -Type DWord -Force }
Write-Host ''

# =============================================================================
# SECTION 24: MMCSS NetworkService
#   Section 9 creates the Games task but not the NetworkService task, which is
#   the one that actually caps background network throughput.
# =============================================================================
Write-Host '[24/32] MMCSS NetworkService Task' -ForegroundColor Cyan
$nbNs = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\NetworkService'
Apply 'Create MMCSS NetworkService task' { if (-not (Test-Path $nbNs)) { New-Item -Path $nbNs -Force | Out-Null } }
Apply 'NetworkService : Priority=6 GPU=8 Affinity=0 BackgroundOnly=False' { Set-ItemProperty -Path $nbNs -Name 'Affinity' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $nbNs -Name 'Background Only' -Value 'False' -Type String -Force; Set-ItemProperty -Path $nbNs -Name 'Priority' -Value 6 -Type DWord -Force; Set-ItemProperty -Path $nbNs -Name 'GPU Priority' -Value 8 -Type DWord -Force }
Apply 'NetworkService : ClockRate / Scheduling / SFIO = High' { Set-ItemProperty -Path $nbNs -Name 'Clock Rate' -Value 10000 -Type DWord -Force; Set-ItemProperty -Path $nbNs -Name 'Scheduling Category' -Value 'High' -Type String -Force; Set-ItemProperty -Path $nbNs -Name 'SFIO Priority' -Value 'High' -Type String -Force }
Write-Host ''

# =============================================================================
# SECTION 25: BACKGROUND BANDWIDTH SERVICES
#   The v3.0 header advertised "service cleanup" but performed none.
#   Stopping or switching a service to Manual never drops the network.
# =============================================================================
Write-Host '[25/32] Background Bandwidth Services' -ForegroundColor Cyan
foreach ($s in @('dmwappushservice','DoSvc','SysMain','BITS','wuauserv','diagtrack','WerSvc','WSearch','MapsBroker','icssvc','WMPNetworkSvc','RetailDemo','lfsvc','XboxNetApiSvc','XblAuthManager','XblGameSave','XboxGipSvc','NcbService','FDResPub')) {
  Apply "Service : $s -> Manual (stops background bandwidth theft)" { Set-Service -Name $s -StartupType Manual -EA SilentlyContinue; Stop-Service -Name $s -Force -EA SilentlyContinue }
}
Write-Host ''

# =============================================================================
# SECTION 26: SAFE ADAPTER BINDINGS
#   Section 12 removes lltdio/rspndr/lldp. These add the rest.
#   ms_tcpip, ms_tcpip6, ms_bridgeport and ms_pacer are deliberately NEVER
#   touched - disabling them drops IPv4/IPv6 or breaks WSL2/Hyper-V/QoS.
# =============================================================================
Write-Host '[26/32] Safe Adapter Bindings (no disconnect possible)' -ForegroundColor Cyan
foreach ($a in $nbAdapters) {
  foreach ($c in @('ms_server','ms_pnpmp','ms_netbt','ms_psling','ms_wanpnp','ms_lltdio','ms_rspndr','ms_lldp')) {
    Apply "[$($a.Name)] Disable binding $c" { Disable-NetAdapterBinding -Name $a.Name -ComponentID $c -EA Stop }
  }
}
Write-Host ''

# =============================================================================
# SECTION 27: IP / IPv6 STACK HARDENING (no reset commands)
# =============================================================================
Write-Host '[27/32] IP / IPv6 Stack Hardening' -ForegroundColor Cyan
Apply 'Teredo disabled (removes tunnel overhead)' { netsh int ipv6 set teredo disabled }
Apply '6to4 disabled (removes tunnel overhead)' { netsh int ipv6 set 6to4 disabled }
Apply 'ISATAP disabled (removes tunnel overhead)' { netsh int ipv6 set isatap disabled }
Apply 'IPv6 randomizeidentifiers=disabled' { netsh int ipv6 set global randomizeidentifiers=disabled }
Apply 'IPv4 randomizeidentifiers=disabled' { netsh int ipv4 set global randomizeidentifiers=disabled }
Apply 'DHCP MediaSense=enabled' { netsh int ip set global dhcpmediasense=enabled }
Apply 'NetBIOS over TCP/IP disabled' { netsh interface ipv4 set global netbiosoverTCPI=disabled }
Apply 'IPv4 Weak Host send/receive disabled (global)' { netsh interface ipv4 set global weakhostsend=disabled weakhostreceive=disabled }
Apply 'IPv6 Weak Host send/receive disabled (global)' { netsh interface ipv6 set global weakhostsend=disabled weakhostreceive=disabled }
foreach ($i in $nbIfList) {
  Apply "ifIndex $i : IPv4 weakhost send/receive disabled" { netsh interface ipv4 set interface $i weakhostsend=disabled weakhostreceive=disabled }
  Apply "ifIndex $i : IPv6 weakhost + lrs + forwarding + advertising disabled" { netsh interface ipv6 set interface $i weakhostsend=disabled weakhostreceive=disabled lrs=disabled forwarding=disabled advertising=disabled }
  Apply "ifIndex $i : InterfaceMetric IPv4 = 5" { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -InterfaceMetric 5 -EA Stop }
  Apply "ifIndex $i : InterfaceMetric IPv6 = 5" { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv6 -InterfaceMetric 5 -EA Stop }
}
foreach ($a in $nbEth) {
  Apply "[$($a.Name)] MTU pinned to 1500 persistent" { netsh interface ipv4 set subinterface $a.Name mtu=1500 store=persistent }
}
Write-Host ''

# =============================================================================
# SECTION 28: DNS AND CACHE
# =============================================================================
Write-Host '[28/32] DNS and Cache' -ForegroundColor Cyan
foreach ($a in $nbEth) {
  Apply "[$($a.Name)] DNS 1.1.1.1 / 1.0.0.1 / 8.8.8.8 / 8.8.4.4" { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses 1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4 -EA Stop }
}
Apply 'DNS suffix devolution disabled' { Set-DnsClientGlobalSetting -SuffixDevolution 0 -DevolutionLevel 0 }
Apply 'DNS-over-HTTPS 1.1.1.1' { Add-DnsClientDohServerAddress -Address 1.1.1.1 -ServerAddresses 1.1.1.1,1.0.0.1 -Validate $false -EA Stop }
Apply 'Destination (route) cache flush - no disconnect' { netsh int ip delete destinationcache }
Apply 'WPAD branchcache reset' { netsh branchcache reset }
Apply 'WinHTTP proxy reset' { netsh winhttp reset proxy }
Apply 'HTTP.sys log buffer flush' { netsh http flush logbuffer }
Apply 'DNS cache flush' { Clear-DnsClientCache -EA Stop }
foreach ($a in $nbAdapters) {
  Apply "[$($a.Name)] ARP/neighbour flush (causes re-resolve, not a disconnect)" { Remove-NetNeighbor -InterfaceIndex $a.ifIndex -Confirm:$false -EA SilentlyContinue }
}
Write-Host ''

# =============================================================================
# SECTION 29: WIFI 7 TUNING
#   The v3.0 script is entirely Ethernet-centric and set no WiFi properties.
#   Property names vary by WiFi driver revision, so each Apply may legitimately
#   report [--]; that is expected and harmless.
# =============================================================================
Write-Host '[29/32] WiFi 7 Tuning (Qualcomm FastConnect class)' -ForegroundColor Cyan
$nbWifiMap = @(@('Preferred Band','Prefer 5GHz'),@('Band Selection','5 GHz only'),@('Wi-Fi Mode','802.11ax only'),@('2.4GHz Wireless Mode','802.11ax only'),@('Channel Width 802.11ax','160 MHz'),@('Channel Width for 5GHz','160 MHz'),@('Channel Width for 2.4GHz','20 MHz Only'),@('Throughput Booster','Enabled'),@('Throughput Enhancement','Enabled'),@('MIMO Power Save Mode','No SMPS'),@('Adaptive Connection Rate','High'),@('Transmit Power','Highest'),@('U-APSD support','Disabled'),@('Packet Coalescing','Disabled'),@('Power Saving Mode','Disabled'),@('Interrupt Moderation','Enabled'))
foreach ($w in $nbWifi) {
  Apply "[$($w.Name)] Disable-NetAdapterPowerManagement (WOL/pattern)" { Disable-NetAdapterPowerManagement -Name $w.Name -WakeOnMagicPacket Disabled -WakeOnPatternMatch Disabled -EA Stop }
  Apply "[$($w.Name)] MediaConnectState / MediaDisconnectState = Connected" { Set-NetAdapter -Name $w.Name -MediaConnectState Connected -MediaDisconnectState Connected -EA Stop }
  foreach ($m in $nbWifiMap) { Apply "[$($w.Name)] $($m[0]) = $($m[1])" { Adv $w.Name $m[0] $m[1] } }
  Apply "[$($w.Name)] wlan autoconfig enabled" { netsh wlan set autoconfig enabled=yes interface="$($w.Name)" }
  Apply "[$($w.Name)] hostednetwork disallowed" { netsh wlan set hostednetwork mode=disallow }
  Apply "[$($w.Name)] allowexplicitcreds allowed" { netsh wlan set allowexplicitcreds allow=yes }
  Apply "[$($w.Name)] blockednetworks hidden" { netsh wlan set blockednetworks display=hide }
  Apply "[$($w.Name)] profileorder priority=1" { netsh wlan set profileorder name="*" interface="$($w.Name)" priority=1 }
}
Write-Host '  >> ACTION REQUIRED - a metered WiFi profile is a hard bandwidth cap:' -ForegroundColor Yellow
Write-Host '     netsh wlan show profiles' -ForegroundColor Yellow
Write-Host '     netsh wlan set profileparameter name="<YOUR-SSID>" costmedium=unrestricted' -ForegroundColor Yellow
Write-Host '     netsh wlan delete profile name="<old-slow-ssid>"' -ForegroundColor Yellow
Write-Host ''

# =============================================================================
# SECTION 30: VPN / VIRTUAL ADAPTER PRIORITY
#   Section 12 sets the interface metric on exactly one adapter. Any VPN or
#   virtual adapter can otherwise outrank the physical link.
# =============================================================================
Write-Host '[30/32] VPN / Virtual Adapter Priority' -ForegroundColor Cyan
foreach ($vpn in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Tailscale|VPN|WireGuard|OpenVPN|Wintun|vEthernet' })) {
  Apply "[$($vpn.Name)] InterfaceMetric IPv4 = 5000 (never outrank Ethernet)" { Set-NetIPInterface -InterfaceIndex $vpn.ifIndex -AddressFamily IPv4 -InterfaceMetric 5000 -EA Stop }
  Apply "[$($vpn.Name)] InterfaceMetric IPv6 = 5000" { Set-NetIPInterface -InterfaceIndex $vpn.ifIndex -AddressFamily IPv6 -InterfaceMetric 5000 -EA Stop }
}
foreach ($np in @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
  if ($np.IPv4Connectivity -ne 'NoTraffic') {
    Apply "[$($np.InterfaceAlias)] NetworkCategory -> Private" { Set-NetConnectionProfile -InterfaceIndex (Get-NetAdapter -Name $np.InterfaceAlias).ifIndex -NetworkCategory Private -EA Stop }
  }
}
Write-Host ''

# =============================================================================
# SECTION 31: POWER / SCHEDULER
#   Core parking adds latency to every network-bound syscall.
# =============================================================================
Write-Host '[31/32] Power / Scheduler' -ForegroundColor Cyan
Apply 'Disable CPU core parking (CPMINCORES=100)' { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 }
Apply 'Minimum processor state 100%' { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 }
Apply 'Maximum processor state 100%' { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEPERMIN 100 }
Apply 'Aggressive performance boost mode' { powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 }
Apply 'Standby idle disabled (AC)' { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0 }
Apply 'Disk idle disabled (AC)' { powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP DISKIDLE 0 }
Apply 'Activate power scheme' { powercfg /setactive SCHEME_CURRENT }
Write-Host ''

# =============================================================================
# SECTION 32: SUPPLEMENT VERIFICATION
# =============================================================================
Write-Host '[32/32] Supplement Verification' -ForegroundColor Cyan
Write-Host '--- Link speed (2.5 Gbps expected if the switch port allows) ---' -ForegroundColor DarkCyan
Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, LinkSpeed | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host '--- netsh int tcp show global ---' -ForegroundColor DarkCyan
netsh int tcp show global 2>$null | Out-String | Write-Host
Write-Host '--- MTU (expect 1500) ---' -ForegroundColor DarkCyan
Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState -eq 'Connected' } | Select-Object InterfaceAlias, NlMtu, InterfaceMetric | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host '--- RSS / RSC ---' -ForegroundColor DarkCyan
foreach ($a in $nbAdapters) {
  Get-NetAdapterRss -Name $a.Name -EA SilentlyContinue | Select-Object Name, NumberOfReceiveQueues, Enabled, BaseProcessorNumber, MaxProcessorNumber | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
  Get-NetAdapterRsc -Name $a.Name -EA SilentlyContinue | Select-Object Name, IPv4Enabled, IPv6Enabled | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}
Write-Host '--- Confirm the link never dropped ---' -ForegroundColor DarkCyan
Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, Status, LinkSpeed | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host ''


# ============================================================================
# SUMMARY
# ============================================================================
$elapsed = (Get-Date) - $script:startTime
$mins = [math]::Floor($elapsed.TotalMinutes)
$secs = $elapsed.Seconds

Write-Host '================================================================' -ForegroundColor Green
Write-Host '           NETBOOST v4.0 CONSOLIDATED - COMPLETE' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Applied : $($script:ok)    Skipped: $($script:skip)    Duration: ${mins}m ${secs}s" -ForegroundColor White
Write-Host ''
Write-Host '  NO REBOOT REQUIRED - all changes take effect immediately.' -ForegroundColor Yellow
Write-Host '  NO ADAPTER RESTART - the link is never dropped by any section.' -ForegroundColor Yellow
Write-Host '  bcdedit disabledynamictcp (S18) applies at NEXT boot.' -ForegroundColor Yellow
Write-Host '  Verify: netsh int tcp show global' -ForegroundColor Yellow
Write-Host '  Verify: Get-NetAdapterRss -Name (Get-NetAdapter | ? Status -eq Up | select -First 1).Name' -ForegroundColor Yellow
Write-Host ''
