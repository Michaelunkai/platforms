# Test-WinupgFastZeroTouch.ps1 - Read-only fast zero-touch checks for winupg work (agents 1-3).
# Does not start Windows Setup, does not reboot, does not modify any file.
$ErrorActionPreference = 'Stop'
$script:failures = 0

function Write-CheckResult {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $suffix = ''
    if ($Detail) { $suffix = " -- $Detail" }
    if ($Passed) { Write-Output ("PASS: {0}{1}" -f $Name, $suffix) }
    else { $script:failures++; Write-Output ("FAIL: {0}{1}" -f $Name, $suffix) }
}

$repairPath = Join-Path $PSScriptRoot 'repair-upgrade.ps1'
$tokens = $null
$parseErrors = $null
$repairAst = [System.Management.Automation.Language.Parser]::ParseFile($repairPath, [ref]$tokens, [ref]$parseErrors)
$repairText = [System.IO.File]::ReadAllText($repairPath)

function Get-RepairFunctionText([string]$Name) {
    $definition = $repairAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | Where-Object Name -eq $Name
    if ($definition) { return $definition.Extent.Text } else { return $null }
}

# (a) full.definitions.ps1 winupg has params StageRoot/EnableAutoLogon/Fast/NoAutoLogon
$defCandidates = @(
    (Join-Path $PSScriptRoot 'full.definitions.ps1'),
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'full.definitions.ps1'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'full.definitions.ps1'),
    'C:\Users\Admin\Documents\WindowsPowerShell\ProfileSources\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1'
)
$defPath = $defCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($defPath) {
    $defText = [System.IO.File]::ReadAllText($defPath)
    $missing = @('StageRoot', 'EnableAutoLogon', 'Fast', 'NoAutoLogon') | Where-Object { $defText -notmatch [regex]::Escape($_) }
    $noWinupg = $defText -notmatch 'winupg'
    if ($noWinupg) { $missing = @('winupg') + @($missing) }
    Write-CheckResult -Name '(a) full.definitions.ps1 winupg params StageRoot/EnableAutoLogon/Fast/NoAutoLogon' -Passed (@($missing).Count -eq 0) -Detail ($(if (@($missing).Count -eq 0) { $defPath } else { "missing: $($missing -join ', ')" }))
} else {
    Write-CheckResult -Name '(a) full.definitions.ps1 winupg params StageRoot/EnableAutoLogon/Fast/NoAutoLogon' -Passed $false -Detail 'full.definitions.ps1 not found'
}

# (b) repair-upgrade.ps1 ExtractDir default contains 'C:\WinSetupCache'
$extractMatch = [regex]::Match($repairText, '\$ExtractDir\s*=\s*"([^"]+)"')
$extractValue = ''
if ($extractMatch.Success) { $extractValue = $extractMatch.Groups[1].Value }
Write-CheckResult -Name "(b) ExtractDir default contains 'C:\WinSetupCache'" -Passed ($extractValue -like '*C:\WinSetupCache*') -Detail "current default: '$extractValue'"

# (c) robocopy args contain MT:16
Write-CheckResult -Name '(c) robocopy args contain MT:16' -Passed ($repairText -match '/MT:16') -Detail ($(if ($repairText -match '/MT:16') { 'found /MT:16' } else { 'found /MT:8 instead' }))

# (d) New-SetupUpgradeArguments: default = real full-screen UI (NO /Quiet); -Quiet adds it
try {
    $newSetupText = Get-RepairFunctionText 'New-SetupUpgradeArguments'
    if (-not $newSetupText) { throw 'function New-SetupUpgradeArguments not found' }
    Invoke-Expression $newSetupText
    $script:RepairUpgradePostBootRoot = Join-Path $PSScriptRoot 'postboot'
    $arguments = New-SetupUpgradeArguments
    $okArgs = ('/Quiet' -notin $arguments) -and ('/PostOOBE' -in $arguments) -and ('/Auto' -in $arguments)
    $quietArgs = New-SetupUpgradeArguments -Quiet
    $okArgs = $okArgs -and ('/Quiet' -in $quietArgs)
    Write-CheckResult -Name '(d) default = full-screen (no /Quiet), -Quiet opts into silent' -Passed $okArgs -Detail ($arguments -join ' ')
} catch {
    Write-CheckResult -Name '(d) default = full-screen (no /Quiet), -Quiet opts into silent' -Passed $false -Detail $_.Exception.Message
}

# (e) Wait loop uses Start-Sleep 4
$waitText = Get-RepairFunctionText 'Wait-RepairUpgradeSetup'
$waitOk = ($null -ne $waitText) -and ($waitText -match 'Start-Sleep\s+-Seconds\s+4\b')
Write-CheckResult -Name '(e) Wait loop uses Start-Sleep 4' -Passed $waitOk -Detail ($(if ($null -eq $waitText) { 'Wait-RepairUpgradeSetup not found' } elseif ($waitOk) { 'found Start-Sleep -Seconds 4' } else { 'still Start-Sleep -Seconds 1' }))

# (f) takeown timeout 15s
$takeownOk = $repairText -match 'takeown[^`r`n]*-TimeoutSeconds\s+15\b'
Write-CheckResult -Name '(f) takeown timeout 15s' -Passed $takeownOk -Detail ($(if ($takeownOk) { 'found takeown -TimeoutSeconds 15' } else { 'current takeown timeouts are 45s/180s' }))

# (g) postboot\ReArm-System.ps1 exists + parses
$rearmPath = Join-Path $PSScriptRoot 'postboot\ReArm-System.ps1'
if (Test-Path -LiteralPath $rearmPath) {
    $rearmTokens = $null
    $rearmErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($rearmPath, [ref]$rearmTokens, [ref]$rearmErrors) | Out-Null
    Write-CheckResult -Name '(g) postboot\ReArm-System.ps1 exists + parses' -Passed (@($rearmErrors).Count -eq 0) -Detail ($(if (@($rearmErrors).Count -eq 0) { 'exists, no parse errors' } else { ($rearmErrors -join '; ') }))
} else {
    Write-CheckResult -Name '(g) postboot\ReArm-System.ps1 exists + parses' -Passed $false -Detail 'file not found'
}

# (h) runtime\agent3-*.txt inserts exist
$agent3Files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'runtime') -Filter 'agent3-*.txt' -ErrorAction SilentlyContinue)
Write-CheckResult -Name '(h) runtime\agent3-*.txt inserts exist' -Passed ($agent3Files.Count -gt 0) -Detail ($(if ($agent3Files.Count -gt 0) { "$($agent3Files.Count) file(s): $(($agent3Files | ForEach-Object Name) -join ', ')" } else { 'no agent3-*.txt files' }))

# (i) winupg fastest-by-default: [switch]$Full present + if (-not $Full) adds -DisableDynamicUpdate
$fastByDefault = $false
if ($defPath) {
    $winupgMatch = [regex]::Match($defText, '(?ms)^\s*function\s+winupg\s*\{.*?\r?\n\}')
    if ($winupgMatch.Success) {
        $wText = $winupgMatch.Value
        $fastByDefault = ($wText -match '\[switch\]\$Full') -and ($wText -match 'if \(-not \$Full\)') -and ($wText -match '-DisableDynamicUpdate')
    }
}
Write-CheckResult -Name '(i) winupg fastest-by-default (-Full opts into DynamicUpdate Enable)' -Passed $fastByDefault -Detail ($(if ($fastByDefault) { 'Full switch + if (-not $Full) => -DisableDynamicUpdate found' } else { 'missing Full switch or fastest-by-default line' }))

# (j) PE fast-path must only validate .dll/.exe (never .cfg/.esd/.wim) - regression for repair-upgrade bug
$peFiltered = $repairText -match '\.\(dll\|exe\)\$' -and $repairText -match 'Test-PortableExecutableFile'
Write-CheckResult -Name '(j) PE fast-path only validates .dll/.exe files' -Passed $peFiltered -Detail ($(if ($peFiltered) { '.dll|.exe extension filter present in Repair-InvalidExtractedPortableExecutables' } else { 'missing extension filter - SetupPlatform.cfg/install.esd would be mis-flagged' }))

# (k) warm-cache image path must index the array ([0]) - regression for Join-Path ChildPath array bug
$warmIndexed = $repairText -match '\$warmImage\[0\]'
Write-CheckResult -Name '(k) warm-cache image uses $warmImage[0] (no array-to-Join-Path)' -Passed $warmIndexed -Detail ($(if ($warmIndexed) { 'Join-Path gets $warmImage[0] scalar' } else { 'Join-Path still receives array - would throw on warm cache' }))

# (l) ReArm schtasks delete must be EAP=Continue guarded - regression for EAP=Stop native-stderr throw
$rearmGuarded = $repairText -match '(?s)WinSetupPostBootReArmSystem.*?\$ErrorActionPreference = .Continue.'
Write-CheckResult -Name '(l) ReArm schtasks delete is EAP=Continue guarded' -Passed $rearmGuarded -Detail ($(if ($rearmGuarded) { 'schtasks /Delete wrapped in EAP=Continue' } else { 'schtasks /Delete under EAP=Stop would throw when task absent' }))

# (m) winupg shows the REAL full-screen Windows Setup (no fake DarkBlue console, -Silent opt-in)
$mOk = $false
if ($defPath) {
    $winupgMatch = [regex]::Match($defText, '(?ms)^\s*function\s+winupg\s*\{.*?\r?\n\}')
    if ($winupgMatch.Success) {
        $wText = $winupgMatch.Value
        $mOk = ($wText -notmatch 'DarkBlue') -and ($wText -match '\[switch\]\$Silent') -and ($wText -match 'Full-Screen Setup') -and ($wText -match "\`$Silent\) \{ \`$defaultArgs \+= '-Silent'")
    }
}
Write-CheckResult -Name '(m) winupg real full-screen Setup (no DarkBlue, -Silent opt-in)' -Passed $mOk -Detail ($(if ($mOk) { 'no DarkBlue; Silent param + passthrough + full-screen notice present' } else { 'winupg still paints DarkBlue or lacks -Silent/full-screen' }))

if ($script:failures -gt 0) {
    Write-Output ("RESULT: {0} check(s) FAILED (expected until agents 1-3 finish)." -f $script:failures)
    exit 1
} else {
    Write-Output 'RESULT: all checks passed.'
    exit 0
}
