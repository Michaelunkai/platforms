<#
.SYNOPSIS
    ws
#>
<#
    Root-Ubuntu wrapper for WSL
      No parameters  ? interactive login shell
      Anything else ? passed verbatim to Bash
      Preserves colours / pager UIs / arrow keys
      Propagates the Linux exit code to PowerShell
#>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Args
    )
    $distro = 'Ubuntu'   # change once if you ever rename
    $user   = 'root'
    $core   = @('-d', $distro, '-u', $user, '--')  # common WSL flags
    if (-not $Args) {
        # ------------- INTERACTIVE -------------
        wsl @core bash -li
    }
    else {
        # -------------- SINGLE COMMAND --------------
        # Re-assemble *exactly* what the caller typed
        $raw     = [string]::Join(' ', $Args)
        $escaped = $raw -replace '"', '\"'  # keep internal quotes intact
        wsl @core bash -li -c "$escaped"
    }
    # Bubble Ubuntu's exit status back out so ; and if ($?) work
    if ($LASTEXITCODE -ne $null) { $global:LASTEXITCODE = $LASTEXITCODE }
