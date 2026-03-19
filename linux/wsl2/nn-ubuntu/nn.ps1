<#
.SYNOPSIS
    nn - PowerShell utility script
.DESCRIPTION
    Extracted from PowerShell profile for modular organization
.NOTES
    Original function: nn
    Location: F:\study\Platforms\linux\wsl2\nn-ubuntu\nn.ps1
    Extracted: 2026-02-19 20:05
#>
param()
    Write-Output "Starting Ubuntu backup/restore cycle..."

    $BackupPath = "F:\backup\linux\wsl\ubuntu.tar"
    $InstallPath = "C:\wsl2\ubuntu\"
    $BackupDir = Split-Path $BackupPath -Parent

    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    Write-Output "Backing up Ubuntu..."
    wsl --export ubuntu $BackupPath
    if ($LASTEXITCODE -eq 0) { Write-Output "Backup complete" }

    Write-Output "Removing Ubuntu..."
    wsl --unregister ubuntu

    if (-not (Test-Path $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null }

    Write-Output "Importing Ubuntu..."
    wsl --import ubuntu $InstallPath $BackupPath
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Import failed"
        return
    }

    Write-Output "Running additional commands..."
    if (Get-Command "rmubu2" -ErrorAction SilentlyContinue) { rmubu2 }
    if (Get-Command "ubuntu2" -ErrorAction SilentlyContinue) { ubuntu2 }
    if (Get-Command "ws" -ErrorAction SilentlyContinue) { ws subit }

    Write-Output "Processing aliases from alias.txt..."

    # Check if alias.txt exists
    if (-not (Test-Path "C:\users\micha\Desktop\alias.txt")) {
        Write-Output "ERROR: alias.txt not found! Skipping alias processing."
    } else {
        Write-Output "alias.txt found, processing..."

        # Create a bash script in WSL to process aliases
        $bashScript = @'
#!/bin/bash
set -e
cp /mnt/c/users/micha/Desktop/alias.txt /tmp/alias_temp.txt
sed -i 's/\r$//' /tmp/alias_temp.txt
while IFS= read -r line; do
  if [[ "$line" =~ ^alias[[:space:]]+([^=]+)= ]]; then
    alias_name="${BASH_REMATCH[1]}"
    echo "  Adding: $alias_name"
    sed -i "/^alias ${alias_name}=/d" /root/.bashrc
    echo "$line" >> /root/.bashrc
  fi
done < /tmp/alias_temp.txt
rm -f /tmp/alias_temp.txt
echo "SUCCESS"
'@

        # Write script to WSL and execute it
        $bashScript | wsl -d ubuntu --exec bash -c "cat > /tmp/process_aliases.sh && chmod +x /tmp/process_aliases.sh && bash /tmp/process_aliases.sh && rm /tmp/process_aliases.sh"

        Write-Output "Aliases updated successfully"
    }

    # Create final backup with the new aliases to make them permanent
    Write-Output "Creating final backup with new aliases..."
    wsl --export ubuntu $BackupPath
    if ($LASTEXITCODE -eq 0) { Write-Output "Final backup complete - aliases are now permanent!" }

    Remove-Item "C:\users\micha\Desktop\alias.txt" -Force -ErrorAction SilentlyContinue
    Write-Output "Done! Aliases are now permanent in /root/.bashrc"
