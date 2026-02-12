# Package Managers & Development Environment Error Detection Module
# Sourced by: a.ps1
# Purpose: Real-time error detection for WinGet, Store, Python, Node, Git, .NET, Java, etc.

param(
    [scriptblock]$ProblemFunc,
    [scriptblock]$CriticalFunc
)

Write-Host "  Checking package managers..." -ForegroundColor DarkCyan

try {
    # ============= WINGET ERRORS =============
    try {
        Write-Host "    WinGet..." -ForegroundColor DarkGray
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Winget-CLI/Operational'; StartTime=$script:lastHour} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Level -le 2 -and $_.Message -match 'error|fail|0x'
        } | ForEach-Object {
            & $ProblemFunc "WINGET ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }

        if (Test-Path "$env:LocalAppData\Microsoft\WinGet\*\error*.txt" -EA 0) {
            Get-ChildItem "$env:LocalAppData\Microsoft\WinGet\*\error*.txt" -EA 0 | ForEach-Object {
                $content = Get-Content $_ -EA 0 | Select-Object -First 3
                if ($content) {
                    & $ProblemFunc "WINGET INSTALL FAIL: $($_.Name) - $($content -join ' | ')"
                }
            }
        }

        if (Test-Path "$env:LocalAppData\Packages\Microsoft.DesktopAppInstaller*\LocalState\*" -EA 0) {
            Get-ChildItem "$env:LocalAppData\Packages\Microsoft.DesktopAppInstaller*\LocalState\*.log" -EA 0 | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object {
                $recentErrors = Select-String -Path $_.FullName -Pattern 'error|failed|0x[0-9A-Fa-f]{8}' -EA 0 | Select-Object -Last 5
                if ($recentErrors) {
                    $recentErrors | ForEach-Object {
                        & $ProblemFunc "WINGET LOG: $($_.Line.Substring(0,[Math]::Min(200,$_.Line.Length)))"
                    }
                }
            }
        }
    } catch {}

    # ============= MICROSOFT STORE ERRORS =============
    try {
        Write-Host "    Store..." -ForegroundColor DarkGray
        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Store/Operational'; StartTime=$script:lastHour} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Level -le 2
        } | ForEach-Object {
            if ($_.Message -match 'Failed to install|Error code|0x[0-9A-Fa-f]{8}|Cannot\s|not\s+found') {
                & $ProblemFunc "STORE ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
            }
        }

        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour; ProviderName='Windows Update for Business'} -EA 0 -MaxEvents 50 | Where-Object {
            $_.Message -match 'Microsoft Store|0x[0-9A-Fa-f]|app.*fail|package.*fail'
        } | ForEach-Object {
            & $ProblemFunc "STORE/UPDATE ERROR: $($_.Message.Substring(0,[Math]::Min(250,$_.Message.Length)))"
        }

        $storeApp = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -EA 0
        if ($storeApp -and $storeApp.Status -ne "Ok") {
            & $ProblemFunc "STORE APP CORRUPTED: Microsoft.DesktopAppInstaller status=$($storeApp.Status)"
        }

        if (Test-Path "$env:LocalAppData\Packages\Microsoft.WindowsStore*\LocalState\cache*" -EA 0) {
            $cacheFiles = Get-ChildItem "$env:LocalAppData\Packages\Microsoft.WindowsStore*\LocalState\cache*" -EA 0
            if ($cacheFiles.Count -gt 1000) {
                & $ProblemFunc "STORE CACHE BLOAT: $($cacheFiles.Count) cache files - may cause slowdown"
            }
        }
    } catch {}

    # ============= PYTHON ERRORS =============
    try {
        Write-Host "    Python..." -ForegroundColor DarkGray
        if (Get-Command python -EA 0) {
            $pythonVer = & python --version 2>&1
            if ($pythonVer -match 'error|not found') {
                & $ProblemFunc "PYTHON: Unable to run - $pythonVer"
            }

            try {
                $importTest = & python -c "import sys; import pip; print('OK')" 2>&1
                if ($importTest -notmatch 'OK') {
                    & $ProblemFunc "PYTHON PIP BROKEN: $importTest"
                }
            } catch {
                & $ProblemFunc "PYTHON: Core modules broken - $($_.Exception.Message.Substring(0, 150))"
            }

            if (Test-Path "$env:AppData\Python" -EA 0) {
                $pythonCache = (Get-ChildItem "$env:AppData\Python" -Recurse -EA 0 | Measure-Object -Property Length -Sum).Sum
                if ($pythonCache -gt 500MB) {
                    & $ProblemFunc "PYTHON CACHE: $([math]::Round($pythonCache/1MB))MB - can be cleaned"
                }
            }
        }

        if (Test-Path ".venv" -EA 0) {
            $venvPython = Get-ChildItem ".venv\Scripts\python.exe" -EA 0
            if (-not $venvPython) {
                & $ProblemFunc "PYTHON VENV BROKEN: Virtual environment missing python.exe"
            }
        }
    } catch {}

    # ============= NODE.JS ERRORS =============
    try {
        Write-Host "    Node.js..." -ForegroundColor DarkGray
        if (Get-Command node -EA 0) {
            $nodeVer = & node --version 2>&1
            if ($nodeVer -match 'error|not found|command') {
                & $ProblemFunc "NODE.JS: Unable to run - $nodeVer"
            }

            if (Get-Command npm -EA 0) {
                $npmVer = & npm --version 2>&1
                if ($npmVer -match 'error|not found|ERESOLVE') {
                    & $ProblemFunc "NPM ERROR: $npmVer"
                }

                try {
                    $npmAudit = & npm audit 2>&1
                    if ($npmAudit -match 'vulnerabilities|audit\s+WARN|error') {
                        $auditMsg = ($npmAudit -join ' ').Substring(0, [Math]::Min(200, ($npmAudit -join ' ').Length))
                        & $ProblemFunc "NPM AUDIT: $auditMsg"
                    }
                } catch {
                    & $ProblemFunc "NPM AUDIT FAILED: $($_.Exception.Message.Substring(0, 150))"
                }
            }

            if (Test-Path "package.json" -EA 0) {
                try {
                    $pkg = Get-Content package.json -Raw | ConvertFrom-Json -EA 0
                    if ($null -eq $pkg.name) {
                        & $ProblemFunc "NODE: package.json invalid - missing 'name' field"
                    }
                } catch {
                    & $ProblemFunc "NODE: package.json corrupted - $($_.Exception.Message.Substring(0, 100))"
                }
            }

            if (Test-Path "node_modules" -EA 0) {
                $nodeModuleSize = (Get-ChildItem "node_modules" -Recurse -EA 0 | Measure-Object -Property Length -Sum).Sum
                if ($nodeModuleSize -gt 1GB) {
                    & $ProblemFunc "NODE: node_modules $([math]::Round($nodeModuleSize/1MB))MB - may need cleanup"
                }
            }
        }

        try {
            $globalModules = & npm ls -g --depth=0 2>&1
            if ($globalModules -match 'ERR!|deprecated|warn') {
                $warns = $globalModules | Where-Object { $_ -match 'ERR!|WARN|deprecated' } | Select-Object -First 3
                $warns | ForEach-Object {
                    & $ProblemFunc "NPM GLOBAL: $($_.Substring(0, [Math]::Min(200, $_.Length)))"
                }
            }
        } catch {}
    } catch {}

    # ============= GIT ERRORS =============
    try {
        Write-Host "    Git..." -ForegroundColor DarkGray
        if (Get-Command git -EA 0) {
            $gitVer = & git --version 2>&1
            if ($gitVer -match 'not found|error') {
                & $ProblemFunc "GIT: Installation broken - $gitVer"
            }

            try {
                $gitConfig = & git config --list 2>&1
                if ($gitConfig -match 'fatal|error') {
                    & $ProblemFunc "GIT CONFIG ERROR: $($gitConfig.Substring(0, 150))"
                }
            } catch {}

            if (Test-Path ".git" -EA 0) {
                try {
                    $gitStatus = & git status 2>&1
                    if ($gitStatus -match 'fatal|error|corrupted') {
                        & $ProblemFunc "GIT REPO CORRUPTED: $($gitStatus.Substring(0, 200))"
                    }
                } catch {
                    & $ProblemFunc "GIT REPO ERROR: $($_.Exception.Message.Substring(0, 150))"
                }
            }
        }
    } catch {}

    # ============= DOTNET ERRORS =============
    try {
        Write-Host "    .NET..." -ForegroundColor DarkGray
        if (Get-Command dotnet -EA 0) {
            $dotnetVer = & dotnet --version 2>&1
            if ($dotnetVer -match 'error|not found') {
                & $ProblemFunc ".NET: Installation broken - $dotnetVer"
            }

            if (Test-Path "$env:UserProfile\.dotnet\temp" -EA 0) {
                $dotnetTempSize = (Get-ChildItem "$env:UserProfile\.dotnet\temp" -Recurse -EA 0 | Measure-Object -Property Length -Sum).Sum
                if ($dotnetTempSize -gt 200MB) {
                    & $ProblemFunc ".NET TEMP: $([math]::Round($dotnetTempSize/1MB))MB accumulated"
                }
            }
        }

        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour; ProviderName='.NET Runtime'} -EA 0 -MaxEvents 50 | Where-Object {
            $_.Level -le 2
        } | ForEach-Object {
            & $ProblemFunc ".NET RUNTIME: $($_.Message.Substring(0, [Math]::Min(250, $_.Message.Length))))"
        }
    } catch {}

    # ============= JAVA ERRORS =============
    try {
        Write-Host "    Java..." -ForegroundColor DarkGray
        if (Get-Command java -EA 0) {
            $javaVer = & java -version 2>&1
            if ($javaVer -match 'not found|error') {
                & $ProblemFunc "JAVA: Installation broken"
            }

            $javaHome = $env:JAVA_HOME
            if ($javaHome -and (Test-Path "$javaHome\lib" -EA 0)) {
                $brokenJars = Get-ChildItem "$javaHome\lib\*.jar" -EA 0 | Where-Object { (Get-Item $_).Length -eq 0 }
                if ($brokenJars) {
                    & $ProblemFunc "JAVA JAR CORRUPTED: $(@($brokenJars).Count) empty jar files"
                }
            }
        }
    } catch {}

    # ============= VCPP REDISTRIBUTABLES =============
    try {
        Write-Host "    VC++..." -ForegroundColor DarkGray
        $vcRuntimes = @(
            "Microsoft Visual C++ 2015-2022 Redistributable",
            "Microsoft Visual C++ 2013 Redistributable",
            "Microsoft Visual C++ 2012 Redistributable"
        )

        $installedSoftware = Get-CimInstance Win32_Product -EA 0 | Select-Object -ExpandProperty Name

        foreach ($vcRuntime in $vcRuntimes) {
            if ($installedSoftware -notcontains $vcRuntime) {
                & $ProblemFunc "MISSING VC++: $vcRuntime not installed - applications may fail"
            }
        }

        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Message -match 'msvcp|vcruntime|msvcr.*dll|LoadLibrary.*VC'
        } | ForEach-Object {
            & $ProblemFunc "VC++ DLL ERROR: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
        }
    } catch {}

    # ============= OPENSSL / CERTIFICATE ERRORS =============
    try {
        Write-Host "    SSL..." -ForegroundColor DarkGray
        if (Get-Command openssl -EA 0) {
            $opensslVer = & openssl version 2>&1
            if ($opensslVer -match 'error|not found') {
                & $ProblemFunc "OPENSSL: Installation broken"
            }
        }

        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$script:lastHour} -EA 0 -MaxEvents 100 | Where-Object {
            $_.Message -match 'certificate|SSL|TLS.*error|Cert.*invalid'
        } | ForEach-Object {
            & $ProblemFunc "CERTIFICATE ERROR: $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))"
        }
    } catch {}

    # ============= BUILD TOOL ERRORS =============
    try {
        Write-Host "    Build tools..." -ForegroundColor DarkGray
        if (Get-Command make -EA 0) {
            $makeVer = & make --version 2>&1 | Select-Object -First 1
            if ($makeVer -match 'error|not found') {
                & $ProblemFunc "MAKE: Installation broken"
            }
        }

        if (Get-Command cmake -EA 0) {
            $cmakeVer = & cmake --version 2>&1 | Select-Object -First 1
            if ($cmakeVer -match 'error|not found') {
                & $ProblemFunc "CMAKE: Installation broken"
            }
        }

        if (Test-Path "$env:LocalAppData\.cmake*" -EA 0) {
            $cmakeCache = (Get-ChildItem "$env:LocalAppData\.cmake*" -Recurse -EA 0 | Measure-Object -Property Length -Sum).Sum
            if ($cmakeCache -gt 500MB) {
                & $ProblemFunc "CMAKE CACHE: $([math]::Round($cmakeCache/1MB))MB - may need cleanup"
            }
        }
    } catch {}

} catch {
    Write-Host "    Error checking package managers: $_" -ForegroundColor DarkRed
}
