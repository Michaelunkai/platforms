[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Interactive,
    [switch]$AllowLegacyMigration
)

$__codexSafeAddTypePath = 'F:\study\Platforms\windows\functions\Invoke-CodexSafePowerShellAddType.ps1'
if ([IO.File]::Exists($__codexSafeAddTypePath)) { . $__codexSafeAddTypePath }
$ErrorActionPreference = 'Stop'
$dockerCli = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$dockerHubUsername = 'michadockermisha'
$credentialPath = Join-Path $env:LOCALAPPDATA 'Codex\DockerCredentials\hub-token.dpapi'

function Get-DockerHubServerUsername {
    try {
        $json = (& $dockerCli info --format '{{json .}}' 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }
        $info = $json | ConvertFrom-Json -ErrorAction Stop
        return [string]$info.Username
    } catch {
        return $null
    }
}

function Get-DockerHubCredentialHelperUsername {
    $configPath = if ($env:DOCKER_CONFIG) {
        Join-Path $env:DOCKER_CONFIG 'config.json'
    } else {
        Join-Path $env:USERPROFILE '.docker\config.json'
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $null }

    try {
        $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json -ErrorAction Stop
        $helperSuffix = [string]$config.credHelpers.'docker.io'
        if (-not $helperSuffix) {
            $helperSuffix = [string]$config.credsStore
        }
        if (-not $helperSuffix) { return $null }
        $helperPath = Join-Path (Split-Path -Parent $dockerCli) ('docker-credential-' + $helperSuffix + '.exe')
        if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { return $null }
        $helperInfo = New-Object Diagnostics.ProcessStartInfo
        $helperInfo.FileName = $helperPath
        $helperInfo.Arguments = 'get'
        $helperInfo.UseShellExecute = $false
        $helperInfo.CreateNoWindow = $true
        $helperInfo.RedirectStandardInput = $true
        $helperInfo.RedirectStandardOutput = $true
        $helperInfo.RedirectStandardError = $true
        $helperProcess = [Diagnostics.Process]::Start($helperInfo)
        $helperOutputTask = $helperProcess.StandardOutput.ReadToEndAsync()
        $helperErrorTask = $helperProcess.StandardError.ReadToEndAsync()
        $helperProcess.StandardInput.WriteLine('https://index.docker.io/v1/')
        $helperProcess.StandardInput.Close()
        if (-not $helperProcess.WaitForExit(10000)) {
            try { $helperProcess.Kill() } catch { }
            return $null
        }
        $helperOutput = $helperOutputTask.Result.Trim()
        $helperExitCode = $helperProcess.ExitCode
        $helperError = $helperErrorTask.Result
        $helperProcess.Dispose()
        if ($helperExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($helperOutput)) { return $null }
        $entry = $helperOutput | ConvertFrom-Json -ErrorAction Stop
        return [string]$entry.Username
    } catch {
        return $null
    }
}

function Get-DockerHubAuthenticatedUsername {
    $serverUsername = Get-DockerHubServerUsername
    if (-not [string]::IsNullOrWhiteSpace($serverUsername)) { return $serverUsername }
    return Get-DockerHubCredentialHelperUsername
}

function Assert-DockerHubLogin {
    param([switch]$AllowDockerCliSuccess)

    $username = Get-DockerHubAuthenticatedUsername
    if ([string]::IsNullOrWhiteSpace($username)) {
        if ($AllowDockerCliSuccess -and (Get-DockerCredentialStoreName) -eq 'desktop') {
            return $dockerHubUsername
        }
        throw 'Docker Hub login could not be verified: the Docker daemon reports no authenticated Hub username.'
    }
    if ($username -ine $dockerHubUsername) {
        throw ('Docker Hub login verified a different username ({0}); expected {1}.' -f $username, $dockerHubUsername)
    }
    return $username
}

function Get-DockerCredentialStoreName {
    $configPath = if ($env:DOCKER_CONFIG) {
        Join-Path $env:DOCKER_CONFIG 'config.json'
    } else {
        Join-Path $env:USERPROFILE '.docker\config.json'
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return 'none' }
    try {
        $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json -ErrorAction Stop
        $hubHelper = [string]$config.credHelpers.'docker.io'
        if ($hubHelper) { return $hubHelper }
        if ([string]$config.credsStore) { return [string]$config.credsStore }
    } catch { }
    return 'file'
}

function Invoke-DockerHubInteractiveLogin {
    Write-Output 'Starting Docker Hub device-code login. Complete the browser confirmation if Docker opens one.'
    & $dockerCli login docker.io
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ('Docker Hub interactive login failed with exit code ' + $exitCode)
    }
    $verifiedUsername = Assert-DockerHubLogin -AllowDockerCliSuccess
    Write-Output ('Docker Hub login verified: username={0} credential_store={1}' -f $verifiedUsername, (Get-DockerCredentialStoreName))
}

function Test-DockerNativeRedirected {
    if (-not ('DockerNativeContextV5' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class DockerNativeContextV5 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern uint GetFinalPathNameByHandle(IntPtr h, StringBuilder b, uint n, uint f);

    public static bool IsRedirected() {
        string path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            ".codex-docker-context-" + Guid.NewGuid().ToString("N") + ".tmp");
        using (var file = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite,
            FileShare.ReadWrite | FileShare.Delete, 1, FileOptions.DeleteOnClose)) {
            var buffer = new StringBuilder(32768);
            if (GetFinalPathNameByHandle(file.SafeFileHandle.DangerousGetHandle(), buffer, 32768, 0) == 0)
                throw new IOException("Cannot identify AppData write path");
            return buffer.ToString().IndexOf("\\Packages\\", StringComparison.OrdinalIgnoreCase) >= 0;
        }
    }
}
'@
    }

    try { return [DockerNativeContextV5]::IsRedirected() }
    catch { return $false }
}

function Get-DockerCredentialPaths {
    $paths = New-Object System.Collections.Generic.List[string]
    [void]$paths.Add($credentialPath)

    $backupCredentialPath = 'F:\backup\codex\latest\desktop-runtime\local-codex\DockerCredentials\hub-token.dpapi'
    if ((Test-Path -LiteralPath $backupCredentialPath -PathType Leaf) -and ($backupCredentialPath -ne $credentialPath)) {
        [void]$paths.Add($backupCredentialPath)
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packageRoot -PathType Container) {
        Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'OpenAI.Codex_*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                [void]$paths.Add((Join-Path $_.FullName 'LocalCache\Local\Codex\DockerCredentials\hub-token.dpapi'))
            }
    }

    $paths | Select-Object -Unique
}

function New-DockerCredentialRecord {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$SecureString,
        [Parameter(Mandatory = $true)][string]$Source,
        [bool]$NeedsMigration = $false
    )
    [pscustomobject]@{
        SecureString = $SecureString
        Source = $Source
        NeedsMigration = $NeedsMigration
    }
}

function Get-DockerHubCredential {
    param([switch]$AllowLegacyMigration)

    foreach ($path in (Get-DockerCredentialPaths)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $encrypted = [IO.File]::ReadAllText($path).Trim()
            if ([string]::IsNullOrWhiteSpace($encrypted)) { continue }
            $secure = ConvertTo-SecureString -String $encrypted -ErrorAction Stop
            return New-DockerCredentialRecord -SecureString $secure -Source $path
        } catch {
            # A credential protected under another Windows profile is not usable here.
        }
    }

    if (-not $AllowLegacyMigration) {
        throw "Docker Hub credential unavailable. No usable current-user DPAPI credential was found at $credentialPath. Run dlog -Interactive to authenticate with Docker Hub's device flow."
    }

    # Explicit opt-in only: older profile backups stored a PAT in a dlog script.
    # Read it only in memory, use stdin for docker login, and migrate it to
    # current-user DPAPI only after Docker Hub accepts it. No credential is
    # written to the command line.
    $legacyPaths = @(
        'F:\backup\windowsapps\profile\backup-data\WindowsPowerShell\Shells\powershell\scripts\misc\dlog\dlog.ps1',
        'F:\backup\windowsapps\profile\profile-backup\WindowsPowerShell\Shells\powershell\scripts\misc\dlog\dlog.ps1',
        'F:\backup\windowsapps\profile\backup-data\WindowsPowerShell\Containers\docker\dlog\dlog.ps1',
        'F:\backup\windowsapps\profile\profile-backup\WindowsPowerShell\Containers\docker\dlog\dlog.ps1'
    )
    $pattern = '(?im)docker\s+login\s+docker\.io\s+(?:--username|-u)\s+(?<username>\S+)\s+(?:--password|-p)\s+(?<secret>\S+)'
    foreach ($path in $legacyPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try { $text = [IO.File]::ReadAllText($path) } catch { continue }
        $match = [regex]::Match($text, $pattern)
        if (-not $match.Success -or $match.Groups['username'].Value -ne $dockerHubUsername) { continue }
        $secure = ConvertTo-SecureString -String $match.Groups['secret'].Value -AsPlainText -Force
        return New-DockerCredentialRecord -SecureString $secure -Source $path -NeedsMigration $true
    }

    throw "Docker Hub credential unavailable. No usable current-user DPAPI credential was found at $credentialPath, and no known legacy login source was available."
}

function Save-DockerCredential {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureString)
    $parent = Split-Path -Parent $credentialPath
    [void][IO.Directory]::CreateDirectory($parent)
    $encrypted = ConvertFrom-SecureString -SecureString $SecureString
    [IO.File]::WriteAllText($credentialPath, $encrypted, [Text.UTF8Encoding]::new($false))
}

if (-not $Interactive -and (Test-DockerNativeRedirected)) {
    $nativeDispatcher = 'F:\study\Platforms\windows\functions\Invoke-DockerNativeScript.ps1'
    if (-not (Test-Path -LiteralPath $nativeDispatcher -PathType Leaf)) {
        throw "Docker native-session dispatcher missing: $nativeDispatcher"
    }
    try {
        & $nativeDispatcher -ScriptPath 'F:\study\Platforms\windows\functions\Invoke-DockerHubLogin.ps1' -Parameters $PSBoundParameters
        return
    } catch {
        # Some non-interactive hosts deny temporary task registration. The direct
        # path below still uses stdin and the same current-user DPAPI candidates.
    }
}

if (-not (Test-Path -LiteralPath $dockerCli -PathType Leaf)) { throw "Docker CLI missing: $dockerCli" }

if (-not $SelfTest) {
    $existingUsername = Get-DockerHubAuthenticatedUsername
    if ($existingUsername) {
        if ($existingUsername -ine $dockerHubUsername) {
            throw ('Docker is already authenticated to Docker Hub as {0}; expected {1}.' -f $existingUsername, $dockerHubUsername)
        }
        Write-Output ('Docker Hub already authenticated: username={0} credential_store={1}' -f $existingUsername, (Get-DockerCredentialStoreName))
        return
    }
}

if ($SelfTest) {
    $credential = Get-DockerHubCredential -AllowLegacyMigration:$AllowLegacyMigration
    try {
        $serverUsername = Get-DockerHubServerUsername
        $helperUsername = Get-DockerHubCredentialHelperUsername
        $authenticatedUsername = if ($serverUsername) { $serverUsername } else { $helperUsername }
        Write-Output ('DLOG_SELFTEST_OK encrypted_credential_readable=true username={0} source={1} server_username={2} helper_username={3} authenticated_username={4} credential_store={5}' -f $dockerHubUsername, $credential.Source, $serverUsername, $helperUsername, $authenticatedUsername, (Get-DockerCredentialStoreName))
    } finally {
        $credential.SecureString.Dispose()
    }
    return
}

if ($Interactive) {
    Invoke-DockerHubInteractiveLogin
    return
}

$credential = $null
try {
    $credential = Get-DockerHubCredential -AllowLegacyMigration:$AllowLegacyMigration
} catch {
    if (-not [Environment]::UserInteractive) { throw }
    Write-Output 'No stored Docker Hub credential found - starting the interactive device-flow login automatically...'
    Invoke-DockerHubInteractiveLogin
    return
}
$secure = $credential.SecureString

try {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $dockerCli
    $info.WorkingDirectory = Split-Path -Parent $dockerCli
    $info.EnvironmentVariables['PATH'] = (Split-Path -Parent $dockerCli) + ';' + $env:PATH
    $info.Arguments = 'login docker.io --username ' + $dockerHubUsername + ' --password-stdin'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true

    $process = [Diagnostics.Process]::Start($info)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $process.StandardInput.WriteLine([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $process.StandardInput.Close()
    }
    if (-not $process.WaitForExit(30000)) {
        try { $process.Kill() } catch { }
        throw 'Docker Hub login exceeded 30 seconds'
    }
    $stdout = $outTask.Result.Trim()
    $stderr = $errTask.Result.Trim()
    if ($process.ExitCode -ne 0) {
        if ($stderr) { throw ('Docker Hub login failed: ' + $stderr) }
        throw ('Docker Hub login failed with exit code ' + $process.ExitCode)
    }

    if ($credential.NeedsMigration) {
        Save-DockerCredential -SecureString $secure
        Write-Output ('Docker Hub credential migrated to current-user DPAPI: {0}' -f $credentialPath)
    }
    if ($stdout) { Write-Output $stdout }
    $verifiedUsername = Assert-DockerHubLogin -AllowDockerCliSuccess
    Write-Output ('Docker Hub login verified: username={0} credential_store={1}' -f $verifiedUsername, (Get-DockerCredentialStoreName))
} finally {
    $secure.Dispose()
}
