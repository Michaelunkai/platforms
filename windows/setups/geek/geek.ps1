<#
.SYNOPSIS
    geek
#>
param (
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Terms
    )
    foreach ($term in $Terms) {
        $formatted = ($term -replace '[\s\-+]', '_').ToLower()
        Start-Process "firefox.exe" "https://www.majorgeeks.com/files/details/$formatted.html"
    }
