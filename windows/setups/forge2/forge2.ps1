<#
.SYNOPSIS
    forge2
#>
param (
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Terms
    )
    foreach ($term in $Terms) {
        $formatted = $term.Replace(' ', '-').ToLower()
        $sfUrl = "https://sourceforge.net/projects/$formatted/files/latest/download"
        try {
            # Follow full redirect chain like a browser
            $finalResponse = Invoke-WebRequest -Uri $sfUrl -MaximumRedirection 10 -Headers @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            } -UseBasicParsing
            $finalUrl = $finalResponse.BaseResponse.ResponseUri.AbsoluteUri
            # Try to get filename from headers or guess
            $fileName = ($finalResponse.Headers['Content-Disposition'] -split 'filename=')[-1].Trim('"')
            if (-not $fileName -or $fileName -eq "") {
                $fileName = "$formatted.exe"
            }
            $outputPath = Join-Path -Path $PWD -ChildPath $fileName
            Invoke-WebRequest -Uri $finalUrl -OutFile $outputPath -UseBasicParsing -Headers @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            }
            Write-Host "? Downloaded: $fileName"
        } catch {
            Write-Warning "? Failed to download from: $sfUrl"
        }
    }
