<#
.SYNOPSIS
    hardware
#>
$system = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -Property Manufacturer, Model, Name, @{Name='TotalPhysicalMemory (GB)'; Expression={[math]::round($_.TotalPhysicalMemory / 1GB, 2)}}
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -Property Name, @{Name='Cores'; Expression={$_.NumberOfCores}}, @{Name='Threads'; Expression={$_.NumberOfLogicalProcessors}}, MaxClockSpeed
    $gpu = Get-CimInstance -ClassName Win32_VideoController | Select-Object -Property Name, @{Name='Memory (GB)'; Expression={[math]::round($_.AdapterRAM / 1GB, 2)}}, DriverVersion
    $ramTotal = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $ramTotalGB = [math]::round($ramTotal.Sum / 1GB, 2)
    $ram = Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object -Property Manufacturer, @{Name='Capacity (GB)'; Expression={[math]::round($_.Capacity / 1GB, 2)}}, Speed
    $disk = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -Property Model, @{Name='Size (GB)'; Expression={[math]::round($_.Size / 1GB, 2)}}
    $bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object -Property Manufacturer, Version, ReleaseDate
    $network = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {$_.NetConnectionStatus -eq 2} | Select-Object -First 1 -Property Name, MACAddress
    "System Information:"
    $system
    "Processor Information:"
    $cpu
    "Graphics Information:"
    $gpu
    "Total RAM (GB): $ramTotalGB"
    "RAM Information:"
    $ram
    "Disk Information:"
    $disk
    "BIOS Information:"
    $bios
    "Primary Network Adapter:"
    $network
