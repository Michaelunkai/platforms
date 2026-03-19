<#
.SYNOPSIS
    wingit2 - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$env:Path += ';C:\Program Files\GitHub CLI;C:\Program Files\Git\cmd;C:\Program Files (x86)\Google\Chrome\Application;C:\Program Files\Seerge\G-Helper;C:\Program Files\Asus\Armoury Crate'; [Environment]::SetEnvironmentVariable('Path', $env:Path, [EnvironmentVariableTarget]::User); winget install --force --accept-package-agreements --accept-source-agreements --ignore-security-hash --skip-dependencies 9NCVDN91XZQP 9MWF2DWS5Z9N google.chrome seerge.g-helper 9N7R5S6B0ZZH GitHub.cli Asus.ArmouryCrate 9WZDNCRDK3WP 9NHPXCXS27F9 KristenMcWilliam.Nyrna Anthropic.Claude Perplexity.Comet 9NT1R1C2HH7J Rclone.Rclone j178.ChatGPT
