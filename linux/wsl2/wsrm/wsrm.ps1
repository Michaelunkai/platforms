<#
.SYNOPSIS
    wsrm
#>
param([Parameter(ValueFromRemainingArguments=$true)]$paths); $allPaths=$paths -join ' ' -split '"' | Where-Object {$_.Trim() -ne ''} | ForEach-Object {$_.Trim()}; foreach($p in $allPaths){try{$item=Get-Item $p -Force -ErrorAction Stop;$parent=$item.PSParentPath -replace '^.*::','';$name=$item.Name;Push-Location $parent;wsl -d ubuntu bash -c "rm -rf '$name'" 2>$null;Pop-Location;Write-Host "Processed: $p" -ForegroundColor Green}catch{if(Test-Path $p -PathType Container){$parent=Split-Path $p -Parent;$name=Split-Path $p -Leaf;Push-Location $parent;wsl -d ubuntu bash -c "rm -rf '$name'" 2>$null;Pop-Location;Write-Host "Processed: $p" -ForegroundColor Green}elseif(Test-Path $p -PathType Leaf){$parent=Split-Path $p -Parent;$name=Split-Path $p -Leaf;Push-Location $parent;wsl -d ubuntu bash -c "rm -rf '$name'" 2>$null;Pop-Location;Write-Host "Processed: $p" -ForegroundColor Green}else{Write-Host "Skipped (not found): $p" -ForegroundColor Yellow}}}
