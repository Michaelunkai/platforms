[CmdletBinding()]
param(
    [string]$Token,
    [switch]$PersistToken
)

# GitHub authentication repair for both gh and Git over HTTPS.
#
# The credential bundle may contain labels and more than one token. Extract
# only token-shaped lines, validate them against GitHub, and let gh store a
# successful credential in its OS credential store. No token is written to a
# file, user environment variable, command-line argument, or output stream.

function Resolve-GitlogGhPath {
    $command = Get-Command -Name 'gh.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }

    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $localAppData = [Environment]::GetEnvironmentVariable('LocalAppData')
    $candidates = @(
        $(if ($programFiles) { Join-Path $programFiles 'GitHub CLI\gh.exe' }),
        $(if ($programFilesX86) { Join-Path $programFilesX86 'GitHub CLI\gh.exe' }),
        $(if ($localAppData) { Join-Path $localAppData 'Programs\GitHub CLI\gh.exe' })
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Resolve-GitlogGitPath {
    $systemGit = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path -LiteralPath $systemGit -PathType Leaf) {
        return $systemGit
    }
    $command = Get-Command -Name 'git.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return $command.Source
    }
    return $null
}

function Add-GitlogCurrentGhPath {
    param([Parameter(Mandatory = $true)][string]$GhPath)

    $directory = Split-Path -Parent $GhPath
    $entries = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($entries | Where-Object { $_.TrimEnd('\') -ieq $directory.TrimEnd('\') }).Count -eq 0) {
        $env:Path = $directory + ';' + $env:Path
    }

    # winget may not refresh PATH for the current account immediately. Persist
    # the CLI directory so later PowerShell sessions can resolve gh.exe too.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($userEntries | Where-Object { $_.TrimEnd('\') -ieq $directory.TrimEnd('\') }).Count -eq 0) {
        [Environment]::SetEnvironmentVariable('Path', (($userEntries + $directory) -join ';'), 'User')
    }
}

function Quote-GitlogProcessArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Stop-GitlogProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }

    $processId = [int]$Process.Id
    $taskkill = Get-Command -Name 'taskkill.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($taskkill) {
        [void](& $taskkill.Source /PID $processId /T /F 2>$null)
    }
    try { $Process.Kill() } catch { }
    try { $Process.WaitForExit(2000) } catch { }
}

function Install-GitlogWingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $winget) {
        return [pscustomobject]@{
            Ok = $false
            Detail = 'winget.exe is unavailable'
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $winget.Source
    $psi.Arguments = "install --id $PackageId --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if (-not $process.WaitForExit(300000)) {
            Stop-GitlogProcessTree -Process $process
            return [pscustomobject]@{
                Ok = $false
                Detail = "$DisplayName installation timed out"
            }
        }

        $process.StandardOutput.ReadToEnd() | Out-Null
        $stderr = $process.StandardError.ReadToEnd().Trim()
        return [pscustomobject]@{
            Ok = ($process.ExitCode -eq 0)
            Detail = $(if ($process.ExitCode -eq 0) { '' } elseif ($stderr) { $stderr } else { "winget exit code $($process.ExitCode)" })
        }
    } catch {
        return [pscustomobject]@{
            Ok = $false
            Detail = $_.Exception.Message
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-GitlogGhProcess {
    param(
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$TokenForProcess,
        [string]$StandardInputText,
        [int]$TimeoutMilliseconds = 60000
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GhPath
    $psi.Arguments = (@($ArgumentList | ForEach-Object { Quote-GitlogProcessArgument ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = -not [string]::IsNullOrEmpty($StandardInputText)
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN')) {
        [void]$psi.EnvironmentVariables.Remove($name)
    }
    if (-not [string]::IsNullOrEmpty($TokenForProcess)) {
        $psi.EnvironmentVariables['GH_TOKEN'] = $TokenForProcess
        $psi.EnvironmentVariables['GITHUB_TOKEN'] = $TokenForProcess
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if (-not [string]::IsNullOrEmpty($StandardInputText)) {
            $process.StandardInput.Write($StandardInputText)
            $process.StandardInput.Close()
        }
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            Stop-GitlogProcessTree -Process $process
            return [pscustomobject]@{
                ExitCode = 124
                TimedOut = $true
                Stdout = ''
                Stderr = 'process timed out'
                Output = 'process timed out'
            }
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $output = (($stdout + "`n" + $stderr).Trim())
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            TimedOut = $false
            Stdout = $stdout
            Stderr = $stderr
            Output = $output
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            TimedOut = $false
            Stdout = ''
            Stderr = $_.Exception.Message
            Output = $_.Exception.Message
        }
    } finally {
        $process.Dispose()
    }
}

function Get-GitlogTokenValues {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $matches = [regex]::Matches(
        $Text,
        '(?m)(?<![A-Za-z0-9_])((?:github_pat_|ghp_)[A-Za-z0-9_]+)(?![A-Za-z0-9_])'
    )
    foreach ($match in $matches) {
        $value = [string]$match.Groups[1].Value
        if ($seen.Add($value)) {
            $value
        }
    }

    if ($matches.Count -eq 0) {
        $trimmed = $Text.Trim()
        if ($trimmed -notmatch '\s' -and $trimmed.Length -ge 20 -and $seen.Add($trimmed)) {
            $trimmed
        }
    }
}

function Get-GitlogTokenCandidates {
    param([string]$ExplicitToken)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $rawInputs = @()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) {
        if (Test-Path -LiteralPath $ExplicitToken -PathType Leaf -ErrorAction SilentlyContinue) {
            $rawInputs += [pscustomobject]@{ Text = [IO.File]::ReadAllText($ExplicitToken); Source = 'argument file' }
        } else {
            $rawInputs += [pscustomobject]@{ Text = $ExplicitToken; Source = 'argument' }
        }
    }

    foreach ($envName in @('GH_TOKEN', 'GITHUB_TOKEN', 'GIT_PAT')) {
        foreach ($scope in @('Process', 'User', 'Machine')) {
            $value = [Environment]::GetEnvironmentVariable($envName, $scope)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $rawInputs += [pscustomobject]@{ Text = $value; Source = "$scope environment $envName" }
            }
        }
    }

    $credentialPath = 'F:\backup\windowsapps\credentials\github\api.txt'
    if (Test-Path -LiteralPath $credentialPath -PathType Leaf) {
        $rawInputs += [pscustomobject]@{
            Text = [IO.File]::ReadAllText($credentialPath)
            Source = $credentialPath
        }
    }

    foreach ($input in $rawInputs) {
        foreach ($value in @(Get-GitlogTokenValues -Text $input.Text)) {
            if ($seen.Add($value)) {
                [pscustomobject]@{ Token = $value; Source = $input.Source }
            }
        }
    }
}

function Get-GitlogGitCredentialCandidate {
    param([Parameter(Mandatory = $true)][string]$GitPath)

    # Reuse a credential already held by Git Credential Manager, but keep the
    # probe non-interactive and bounded. The password is returned only in
    # memory so it can be validated and, if requested, handed to gh via stdin.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GitPath
    $psi.Arguments = 'credential fill'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN')) {
        [void]$psi.EnvironmentVariables.Remove($name)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $newline = [Environment]::NewLine
        $process.StandardInput.Write(("protocol=https{0}host=github.com{0}{0}" -f $newline))
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(10000)) {
            Stop-GitlogProcessTree -Process $process
            return $null
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $process.StandardError.ReadToEnd() | Out-Null
        if ($process.ExitCode -ne 0) {
            return $null
        }

        $passwordLine = @(
            $stdout -split '\r?\n' |
                Where-Object { $_ -like 'password=*' } |
                Select-Object -First 1
        )
        if ($passwordLine.Count -eq 0) {
            return $null
        }

        $password = $passwordLine[0].Substring(9).Trim()
        if ([string]::IsNullOrWhiteSpace($password)) {
            return $null
        }
        return [pscustomobject]@{
            Token = $password
            Source = 'Git Credential Manager'
        }
    } catch {
        return $null
    } finally {
        $process.Dispose()
    }
}

function Get-GitlogStoredLogin {
    param([Parameter(Mandatory = $true)][string]$GhPath)

    $probe = Invoke-GitlogGhProcess -GhPath $GhPath -ArgumentList @('api', 'user', '--jq', '.login')
    if ($probe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe.Stdout)) {
        return $probe.Stdout.Trim()
    }
    return $null
}

function Test-GitlogToken {
    param(
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string]$CandidateToken
    )

    $probe = Invoke-GitlogGhProcess -GhPath $GhPath -ArgumentList @('api', 'user', '--jq', '.login') -TokenForProcess $CandidateToken
    if ($probe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe.Stdout)) {
        return [pscustomobject]@{
            Ok = $true
            Login = $probe.Stdout.Trim()
        }
    }
    return [pscustomobject]@{
        Ok = $false
        Login = ''
    }
}

function Invoke-GitlogGitCredentialProbe {
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)][string]$Login
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GitPath
    $psi.Arguments = 'credential fill'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN')) {
        [void]$psi.EnvironmentVariables.Remove($name)
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $process.StandardInput.Write("protocol=https`nhost=github.com`nusername=$Login`n`n")
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            Stop-GitlogProcessTree -Process $process
            return [pscustomobject]@{ Ok = $false; TimedOut = $true; ExitCode = 124 }
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.StandardError.ReadToEnd() | Out-Null
        return [pscustomobject]@{
            Ok = ($process.ExitCode -eq 0 -and $stdout -match '(?m)^password=.+')
            TimedOut = $false
            ExitCode = [int]$process.ExitCode
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; TimedOut = $false; ExitCode = 1 }
    } finally {
        $process.Dispose()
    }
}

function Invoke-GitlogGitProbe {
    param([Parameter(Mandatory = $true)][string]$GitPath)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GitPath
    $psi.Arguments = 'ls-remote --exit-code https://github.com/cli/cli.git HEAD'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        if (-not $process.WaitForExit(30000)) {
            Stop-GitlogProcessTree -Process $process
            return [pscustomobject]@{ Ok = $false; TimedOut = $true; ExitCode = 124 }
        }
        $process.StandardOutput.ReadToEnd() | Out-Null
        $process.StandardError.ReadToEnd() | Out-Null
        return [pscustomobject]@{
            Ok = ($process.ExitCode -eq 0)
            TimedOut = $false
            ExitCode = [int]$process.ExitCode
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; TimedOut = $false; ExitCode = 1 }
    } finally {
        $process.Dispose()
    }
}

function Set-GitlogGitHelper {
    param(
        [Parameter(Mandatory = $true)][string]$GhPath,
        [Parameter(Mandatory = $true)][string]$GitPath
    )

    $setup = Invoke-GitlogGhProcess -GhPath $GhPath -ArgumentList @('auth', 'setup-git', '--hostname', 'github.com')
    if ($setup.ExitCode -ne 0) {
        return $false
    }
    $helpers = @(& $GitPath config --global --get-all 'credential.https://github.com.helper' 2>$null)
    return @($helpers | Where-Object { $_ -match '(?i)^\s*!.*auth\s+git-credential\b' }).Count -gt 0
}

$ghPath = Resolve-GitlogGhPath
if (-not $ghPath) {
    Write-Host '[gitlog] GitHub CLI is missing; installing it with winget.' -ForegroundColor Yellow
    $install = Install-GitlogWingetPackage -PackageId 'GitHub.cli' -DisplayName 'GitHub CLI'
    $ghPath = Resolve-GitlogGhPath
    if (-not $install.Ok -or -not $ghPath) {
        Write-Error ("GitHub CLI could not be installed automatically: {0}" -f $install.Detail)
        $global:LASTEXITCODE = 127
        return
    }
}
Add-GitlogCurrentGhPath -GhPath $ghPath

$gitPath = Resolve-GitlogGitPath
if (-not $gitPath) {
    Write-Host '[gitlog] Git is missing; installing it with winget.' -ForegroundColor Yellow
    $install = Install-GitlogWingetPackage -PackageId 'Git.Git' -DisplayName 'Git'
    $gitPath = Resolve-GitlogGitPath
    if (-not $install.Ok -or -not $gitPath) {
        Write-Error ("Git could not be installed automatically: {0}" -f $install.Detail)
        $global:LASTEXITCODE = 127
        return
    }
}

$login = Get-GitlogStoredLogin -GhPath $ghPath
$credentialSource = 'gh credential store'

if ([string]::IsNullOrWhiteSpace($login)) {
    $validCandidate = $null
    $managerCandidate = Get-GitlogGitCredentialCandidate -GitPath $gitPath
    $candidates = @()
    if ($managerCandidate) {
        $candidates += $managerCandidate
    }
    $candidates += @(Get-GitlogTokenCandidates -ExplicitToken $Token)

    foreach ($candidate in $candidates) {
        $test = Test-GitlogToken -GhPath $ghPath -CandidateToken $candidate.Token
        if ($test.Ok) {
            $validCandidate = $candidate
            $login = $test.Login
            break
        }
    }

    if ($validCandidate) {
        $loginResult = Invoke-GitlogGhProcess -GhPath $ghPath `
            -ArgumentList @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--with-token') `
            -StandardInputText ($validCandidate.Token + "`n")
        if ($loginResult.ExitCode -ne 0) {
            Write-Error 'GitHub rejected the candidate credential while saving it through gh.'
            $global:LASTEXITCODE = 1
            return
        }
        $credentialSource = $validCandidate.Source
        $login = Get-GitlogStoredLogin -GhPath $ghPath
    }
}

if ([string]::IsNullOrWhiteSpace($login)) {
    Write-Host '[gitlog] Browserless mode: no valid GitHub credential was found in gh, Git Credential Manager, the environment, or the configured token files.' -ForegroundColor Yellow
    Write-Host '[gitlog] Provide a newly valid PAT with: gitlog -Token <token-or-file> (it will persist automatically).' -ForegroundColor Yellow
    $global:LASTEXITCODE = 2
    return [pscustomobject]@{
        Success = $false
        Login = ''
        NeedsBrowserLogin = $false
        NeedsValidToken = $true
        CredentialPath = 'F:\backup\windowsapps\credentials\github\api.txt'
    }
}

$helperOk = Set-GitlogGitHelper -GhPath $ghPath -GitPath $gitPath
$status = Invoke-GitlogGhProcess -GhPath $ghPath -ArgumentList @('auth', 'status', '--hostname', 'github.com')
$identity = Get-GitlogStoredLogin -GhPath $ghPath
$credentialProbe = Invoke-GitlogGitCredentialProbe -GitPath $gitPath -Login $login
$gitProbe = Invoke-GitlogGitProbe -GitPath $gitPath

$success = ($status.ExitCode -eq 0 -and $identity -eq $login -and $helperOk -and $credentialProbe.Ok -and $gitProbe.Ok)
$global:LASTEXITCODE = if ($success) { 0 } else { 1 }

if ($success) {
    Write-Host ("[gitlog] GitHub authentication is active for {0}; gh and Git HTTPS credential helper verified." -f $login) -ForegroundColor Green
} else {
    Write-Host ("[gitlog] Authentication identity={0}, ghStatus={1}, gitHelper={2}, credentialProbe={3}, gitProbe={4}." -f
        $identity, ($status.ExitCode -eq 0), $helperOk, $credentialProbe.Ok, $gitProbe.Ok) -ForegroundColor Yellow
}

[pscustomobject]@{
    Success = $success
    Login = $login
    GhPath = $ghPath
    GitPath = $gitPath
    CredentialSource = $credentialSource
    GhStatusOk = ($status.ExitCode -eq 0)
    GitHelperConfigured = $helperOk
    GitCredentialProbeOk = $credentialProbe.Ok
    GitLsRemoteProbeOk = $gitProbe.Ok
    PersistedInGhStore = $true
}
