<#
.SYNOPSIS
    short3 - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: short3
    Location: F:\study\Platforms\windows\tools\game-shortcuts-v3\short3.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    $basePath = "F:\backup\windowsapps\installed"
    $shell = New-Object -ComObject WScript.Shell
    $processedFolders = @{}
    $totalFolders = 0
    $shortcutsCreated = 0
    $shortcutsSkipped = 0
    $shortcutsRemoved = 0
    # Function to find the main executable in a folder
    function Find-MainExecutable {
        param (
            [string]$folderPath
        )
        # Look for executables directly in this folder
        $exeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
        # First priority: Look for exe files with names matching the parent folder name
        $folderName = Split-Path -Path $folderPath -Leaf
        $matchingExe = $exeFiles | Where-Object {
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            return $exeName -eq $folderName -or
                   $exeName -eq "$folderName-win64" -or
                   $exeName -eq "$folderName-win32" -or
                   $exeName -eq "app" -or
                   $exeName -eq "launcher" -or
                   $exeName -eq "main"
        } | Select-Object -First 1
        if ($matchingExe) {
            return $matchingExe.FullName
        }
        # Second priority: Look for exe files in specific subfolders
        $commonSubfolders = @("bin", "app", "program", "dist", "build", "release")
        foreach ($subFolder in $commonSubfolders) {
            $subFolderPath = Join-Path -Path $folderPath -ChildPath $subFolder
            if (Test-Path -Path $subFolderPath -PathType Container) {
                $subFolderExes = Get-ChildItem -Path $subFolderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
                $subFolderMatchingExe = $subFolderExes | Where-Object {
                    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    return $exeName -eq $folderName -or
                           $exeName -eq "$folderName-win64" -or
                           $exeName -eq "$folderName-win32" -or
                           $exeName -eq "app" -or
                           $exeName -eq "launcher" -or
                           $exeName -eq "main"
                } | Select-Object -First 1
                if ($subFolderMatchingExe) {
                    return $subFolderMatchingExe.FullName
                }
            }
        }
        # Third priority: Simply take the largest exe file (assuming it's the main application)
        if ($exeFiles.Count -gt 0) {
            return ($exeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        # If no exe found directly, try to find the biggest one recursively
        $allExeFiles = Get-ChildItem -Path $folderPath -Filter "*.exe" -File -Recurse -ErrorAction SilentlyContinue
        if ($allExeFiles.Count -gt 0) {
            return ($allExeFiles | Sort-Object Length -Descending | Select-Object -First 1).FullName
        }
        return $null
    }
    # Function to manage shortcuts in a folder - ensure only one exists
    
    # Process all folders recursively
    function Process-Folders {
        param (
            [string]$currentPath
        )
        $folders = Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            # Skip if this folder has already been processed
            if ($processedFolders.ContainsKey($folder.FullName)) {
                continue
            }
            $processedFolders[$folder.FullName] = $true
            $script:totalFolders++
            # Find the main executable
            $mainExe = Find-MainExecutable -folderPath $folder.FullName
            # Manage shortcuts - ensure only one exists
            Manage-Shortcuts -folderPath $folder.FullName -mainExePath $mainExe
            # Process subfolders
            Process-Folders -currentPath $folder.FullName
        }
    }
    # Main execution
    Write-Output "Starting to process folders in $basePath..." -ForegroundColor Magenta
    Process-Folders -currentPath $basePath
    # Release COM object
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) > $null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    # Summary
    Write-Output "`nProcess completed!" -ForegroundColor Green
    Write-Output "Total folders processed: $totalFolders" -ForegroundColor White
    Write-Output "Shortcuts created: $shortcutsCreated" -ForegroundColor Green
    Write-Output "Folders skipped (already had valid shortcuts): $shortcutsSkipped" -ForegroundColor Cyan
    Write-Output "Extra shortcuts removed: $shortcutsRemoved" -ForegroundColor Yellow
