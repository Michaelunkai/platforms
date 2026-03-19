<#
.SYNOPSIS
    disks - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
(Get-PSDrive -PSProvider FileSystem).Name | % { $p="$($_):\test.tmp"; try { $sw=[Diagnostics.Stopwatch]::StartNew(); [IO.File]::WriteAllBytes($p,(New-Object byte[] 1GB)); $sw.Stop(); "$($_): $([math]::Round(1024/$sw.Elapsed.TotalSeconds,2)) MB/s"; Remove-Item $p -Force } catch { "$($_): Access denied or read-only" } }
