<#
.SYNOPSIS
    specs - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: specs
    Location: F:\study\Platforms\windows\tools\system-specs\specs.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    Write-Output "Collecting selected laptop hardware specifications..." -ForegroundColor Green
    Write-Output "=====================================================" -ForegroundColor Green
    # Get OS information (Exact OS name and architecture)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, OSArchitecture
    Write-Output "`n--- Operating System ---" -ForegroundColor Cyan
    Write-Output ("OS: " + $os.Caption)
    Write-Output ("Architecture: " + $os.OSArchitecture)
    # Get full product model from the computer system
    $system = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object Manufacturer, Model
    Write-Output "`n--- Computer System ---" -ForegroundColor Cyan
    Write-Output ("Manufacturer: " + $system.Manufacturer)
    Write-Output ("Full Product Model: " + $system.Model)
    # Get GPU information (Name of video controller)
    $gpu = Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1 Name
    Write-Output "`n--- Graphics Processing Unit ---" -ForegroundColor Cyan
    Write-Output ("GPU: " + $gpu.Name)
    # Get CPU information (Exact CPU name, cores, and logical processors)
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
    Write-Output "`n--- Central Processing Unit ---" -ForegroundColor Cyan
    Write-Output ("CPU: " + $cpu.Name)
    Write-Output ("Cores: " + $cpu.NumberOfCores + " | Logical Processors: " + $cpu.NumberOfLogicalProcessors)
    # Get RAM information (Total Physical Memory in GB)
    $totalRAM = [Math]::Round($system.TotalPhysicalMemory / 1GB, 2)
    Write-Output "`n--- Memory ---" -ForegroundColor Cyan
    Write-Output ("Installed RAM: " + $totalRAM + " GB")
    # Get Storage information (Disk drive type and capacity)
    Write-Output "`n--- Storage ---" -ForegroundColor Cyan
    $drives = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, InterfaceType, Size
    foreach ($drive in $drives) {
        $sizeGB = [Math]::Round($drive.Size / 1GB, 2)
        Write-Output ("Drive: " + $drive.Model)
        Write-Output ("Type: " + $drive.InterfaceType + " | Capacity: " + $sizeGB + " GB")
    }
    # Get Motherboard information
    $board = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber
    Write-Output "`n--- Motherboard ---" -ForegroundColor Cyan
    Write-Output ("Manufacturer: " + $board.Manufacturer)
    Write-Output ("Product: " + $board.Product)
    Write-Output ("Serial Number: " + $board.SerialNumber)
    # Get BIOS serial number (if different from the motherboard)
    $bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object -First 1 SerialNumber
    Write-Output "`n--- System Serial Number ---" -ForegroundColor Cyan
    Write-Output ("BIOS Serial Number: " + $bios.SerialNumber)
    # Determine BIOS update support URL based on motherboard manufacturer.
    Write-Output "`n--- BIOS Update ---" -ForegroundColor Cyan
    $manufacturer = $board.Manufacturer
    $biosUpdateURL = switch -Wildcard ($manufacturer) {
        "*Dell*"         { "https://www.dell.com/support/home/en-us/drivers" ; break }
        "*HP*"           { "https://support.hp.com/us-en/drivers" ; break }
        "*Lenovo*"       { "https://pcsupport.lenovo.com/us/en/solutions/ht502081" ; break }
        "*ASUS*"         { "https://www.asus.com/support/" ; break }
        "*MSI*"          { "https://www.msi.com/support/download" ; break }
        Default          { "https://www.google.com/search?q=" + $manufacturer + "+BIOS+update" }
    }
    Write-Output "To update your BIOS drivers, run the one-liner command below:"
    Write-Output "Start-Process '$biosUpdateURL'"
