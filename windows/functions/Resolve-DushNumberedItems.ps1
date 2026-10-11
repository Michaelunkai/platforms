function global:Resolve-DushNumberedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Selection,
        [switch]$DirectoriesOnly
    )

    $cachePath = 'C:\ProgramData\ForceDeleteAnything\last-numbered-items.tsv'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        Write-Host '[dush] numbered list is unavailable; run dush in the target folder first.' -ForegroundColor Yellow
        return @()
    }

    try {
        $cacheItem = Get-Item -LiteralPath $cachePath -ErrorAction Stop
    } catch {
        Write-Host '[dush] numbered list disappeared while it was being read; run dush again.' -ForegroundColor Yellow
        return @()
    }
    $age = (Get-Date).ToUniversalTime() - $cacheItem.LastWriteTimeUtc
    if ($age.TotalMinutes -gt 30) {
        Write-Host '[dush] numbered list is older than 30 minutes; run dush again before using its numbers.' -ForegroundColor Yellow
        return @()
    }

    try {
        $location = Get-Location -ErrorAction Stop
    } catch {
        Write-Host '[dush] current location is unavailable; run dush again from a FileSystem folder.' -ForegroundColor Yellow
        return @()
    }
    if (-not $location -or $location.Provider.Name -ne 'FileSystem') {
        Write-Host '[dush] numbered selections require a FileSystem location; run dush again there.' -ForegroundColor Yellow
        return @()
    }

    $root = $null
    $rows = @{}
    foreach ($line in @(Get-Content -LiteralPath $cachePath -Encoding UTF8)) {
        $text = [string]$line
        if ($text.StartsWith('#')) { continue }
        if ($text.StartsWith('root=', [System.StringComparison]::OrdinalIgnoreCase)) {
            $root = $text.Substring(5)
            continue
        }
        if ($text -match '^(\d+)\t(.+)$') {
            $rows[[int]$matches[1]] = $matches[2]
        }
    }

    if ([string]::IsNullOrWhiteSpace($root) -or $rows.Count -eq 0) {
        Write-Host '[dush] numbered list contains no usable root or rows; run dush again.' -ForegroundColor Yellow
        return @()
    }

    $normalize = {
        param([string]$Value)
        $candidate = [Environment]::ExpandEnvironmentVariables($Value.Trim())
        if ($candidate.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = '\\' + $candidate.Substring(8)
        } elseif ($candidate.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $candidate = $candidate.Substring(4)
        }
        try {
            return ([IO.Path]::GetFullPath($candidate)).TrimEnd('\')
        } catch {
            return $candidate.TrimEnd('\')
        }
    }

    $cacheRoot = & $normalize $root
    $currentRoot = & $normalize ([string]$location.ProviderPath)
    if ($cacheRoot -ine $currentRoot) {
        Write-Host ("[dush] numbered list is for '{0}', but the current folder is '{1}'; run dush here before using its numbers." -f $cacheRoot, $currentRoot) -ForegroundColor Yellow
        return @()
    }
    if (-not [IO.Directory]::Exists($cacheRoot)) {
        Write-Host "[dush] numbered root is already absent: $cacheRoot" -ForegroundColor Yellow
        return @()
    }

    $numberPattern = '^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$'
    $resolved = New-Object 'System.Collections.Generic.List[object]'
    foreach ($rawSelection in $Selection) {
        $selector = ([string]$rawSelection).Trim()
        if ([string]::IsNullOrWhiteSpace($selector) -or $selector -notmatch $numberPattern) {
            Write-Host "[dush] invalid numbered selection '$rawSelection'; run dush again and use a listed number." -ForegroundColor Yellow
            return @()
        }

        foreach ($part in $selector.Split(',')) {
            $bounds = $part.Split('-')
            $first = 0
            $last = 0
            if (-not [int]::TryParse($bounds[0], [ref]$first) -or $first -lt 1) {
                Write-Host "[dush] invalid numbered selection '$part'; run dush again and use a listed number." -ForegroundColor Yellow
                return @()
            }
            if ($bounds.Count -eq 1) {
                $last = $first
            } elseif ($bounds.Count -eq 2 -and
                [int]::TryParse($bounds[1], [ref]$last) -and $last -ge $first) {
                if (($last - $first) -gt 100000) {
                    Write-Host "[dush] numbered range '$part' is too large; use a smaller selection." -ForegroundColor Yellow
                    return @()
                }
            } else {
                Write-Host "[dush] invalid descending numbered range '$part'; run dush again." -ForegroundColor Yellow
                return @()
            }

            for ($index = $first; $index -le $last; $index++) {
                if (-not $rows.ContainsKey($index)) {
                    Write-Host "[dush] number $index is unavailable; the folder may have been removed. Run dush again." -ForegroundColor Yellow
                    return @()
                }

                $path = [string]$rows[$index]
                $literalPath = $path
                if (-not (Test-Path -LiteralPath $literalPath)) {
                    $extendedPath = '\\?\' + $path
                    if ([IO.File]::Exists($extendedPath) -or [IO.Directory]::Exists($extendedPath)) {
                        $literalPath = $extendedPath
                    }
                }
                $exists = [IO.File]::Exists($literalPath) -or [IO.Directory]::Exists($literalPath)
                if ($DirectoriesOnly -and $exists -and -not [IO.Directory]::Exists($literalPath)) {
                    Write-Host "[dush] numbered item $index is a file, not a directory: $path" -ForegroundColor Yellow
                    continue
                }

                $name = [IO.Path]::GetFileName($path.TrimEnd('\'))
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $path }
                [void]$resolved.Add([pscustomobject]@{
                    Index = $index
                    Name = $name
                    Path = $literalPath
                    Root = $cacheRoot
                    Exists = $exists
                })
            }
        }
    }

    return $resolved.ToArray()
}
