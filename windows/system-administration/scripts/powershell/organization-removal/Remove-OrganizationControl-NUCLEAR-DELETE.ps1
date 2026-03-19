#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NUCLEAR option - completely DELETES enrollment keys using takeown + icacls

.DESCRIPTION
    Uses Windows takeown and icacls to take ownership and grant permissions,
    then DELETES the enrollment keys entirely to remove the Settings banner.
#>

$ErrorActionPreference = 'Continue'

Write-Host "`n================================================================" -ForegroundColor Red
Write-Host "  NUCLEAR ENROLLMENT KEY DELETION" -ForegroundColor Red
Write-Host "  This will FORCE DELETE the protected registry keys" -ForegroundColor Red
Write-Host "================================================================`n" -ForegroundColor Red

# Get list of enrollment GUIDs
$enrollments = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue

if (-not $enrollments) {
    Write-Host "✅ No enrollment keys found - nothing to delete!" -ForegroundColor Green
    exit 0
}

Write-Host "Found $($enrollments.Count) enrollment keys to delete`n" -ForegroundColor Yellow

$success = 0
$failed = 0

foreach ($enrollment in $enrollments) {
    $guid = $enrollment.PSChildName
    $regPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Enrollments\$guid"
    
    Write-Host "Processing: $guid" -ForegroundColor Cyan
    
    # Step 1: Take ownership using takeown
    Write-Host "  1. Taking ownership..." -ForegroundColor Gray
    $takeownResult = takeown /F "Registry\Machine\SOFTWARE\Microsoft\Enrollments\$guid" /R /A 2>&1
    
    # Step 2: Grant full control using icacls
    Write-Host "  2. Granting permissions..." -ForegroundColor Gray
    $icaclsResult = icacls "Registry\Machine\SOFTWARE\Microsoft\Enrollments\$guid" /grant "Administrators:F" /T /C 2>&1
    
    # Step 3: Delete using reg delete
    Write-Host "  3. Deleting key..." -ForegroundColor Gray
    $deleteResult = reg delete $regPath /f 2>&1
    
    # Step 4: Verify deletion
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments\$guid")) {
        Write-Host "  ✅ SUCCESS - Key deleted!" -ForegroundColor Green
        $success++
    } else {
        Write-Host "  ❌ FAILED - Key still exists" -ForegroundColor Red
        $failed++
    }
    
    Write-Host ""
}

# Try to delete the parent Enrollments key if all children are gone
Write-Host "Attempting to delete parent Enrollments key..." -ForegroundColor Cyan
$remaining = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue

if (-not $remaining) {
    Write-Host "  No child keys remaining, deleting parent..." -ForegroundColor Gray
    $deleteParent = reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Enrollments" /f 2>&1
    
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments")) {
        Write-Host "  ✅ Parent key deleted!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Parent key still exists (protected by Windows)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠️  Some child keys still exist, parent cannot be deleted" -ForegroundColor Yellow
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  OPERATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green

Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  Deleted: $success" -ForegroundColor Green
Write-Host "  Failed:  $failed" -ForegroundColor Red

if ($failed -eq 0) {
    Write-Host "`n✅ ALL ENROLLMENT KEYS DELETED!" -ForegroundColor Green
    Write-Host "`n⚠️  REBOOT NOW to see the Settings banner disappear!" -ForegroundColor Yellow
    Write-Host "`nAfter reboot:" -ForegroundColor Cyan
    Write-Host "  1. Open Settings" -ForegroundColor White
    Write-Host "  2. Go to Accounts > Access work or school" -ForegroundColor White
    Write-Host "  3. The 'Managed by organization' banner will be GONE!" -ForegroundColor White
} else {
    Write-Host "`n⚠️  Some keys could not be deleted (kernel-level protection)" -ForegroundColor Yellow
    Write-Host "`nThe Settings banner may still appear until Windows is reinstalled." -ForegroundColor Yellow
}

Write-Host "`n================================================================`n" -ForegroundColor Green
