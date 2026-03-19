<#
.SYNOPSIS
    forge
#>
param (
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Terms
    )
    foreach ($term in $Terms) {
        $formatted = $term.Replace(' ', '-').ToLower()
        firefox "https://sourceforge.net/projects/$formatted/files/latest/download"
    }
