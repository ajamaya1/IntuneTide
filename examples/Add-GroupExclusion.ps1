#Requires -Version 7.2
<#
.SYNOPSIS
    Bulk-add a group EXCLUSION to Intune configuration profiles (or any other
    assignable area). Previews by default — writes only with -Apply.

.DESCRIPTION
    Adds an exclusionGroupAssignmentTarget for one group across many resources in
    a single pass. The write is a read-merge-write: existing include assignments,
    filters and intents on each profile are preserved, and the exclusion is added
    alongside them. Nothing is ever replaced.

    Safe to re-run. A profile that already excludes the group is reported as
    'already assigned' and skipped, and each profile is written independently so
    one failure never aborts the batch.

    Run it once to read the plan, then again with -Apply to commit.

.PARAMETER Group
    Group display name or object id to exclude.

.PARAMETER Area
    Which assignable areas to touch. Default 'Configuration', which covers all
    three profile families: settings catalog, device configuration profiles and
    ADMX administrative templates. Other values: Compliance, Apps, Scripts,
    'App protection', 'Windows Update', 'Endpoint security', Remediations,
    Enrollment, 'Cloud PC', 'Scope tags'. Pass several, or 'All' for everything.

.PARAMETER NameLike
    Only profiles whose name contains this text (case-insensitive substring).
    This is how you narrow to a subset instead of the whole area.

.PARAMETER Apply
    Actually write. Without it the script only prints the plan.

.PARAMETER ReceiptPath
    CSV receipt of what was written (default: exclusion-receipt-<timestamp>.csv
    next to the script when -Apply is used). Attach it to the change ticket.

.PARAMETER TenantId / ClientId / ClientSecret / CertificateThumbprint
    Optional app-only sign-in for unattended runs. Omit them all to sign in
    interactively, or to reuse a session you already connected.

.PARAMETER SkipConnect
    Use the current Graph session as-is; do not attempt to sign in.

.EXAMPLE
    ./Add-GroupExclusion.ps1 -Group "VIP Executives"

    Preview: exclude that group from every configuration profile. No writes.

.EXAMPLE
    ./Add-GroupExclusion.ps1 -Group "VIP Executives" -Apply

    Commit the exclusion across every configuration profile.

.EXAMPLE
    ./Add-GroupExclusion.ps1 -Group "Kiosks" -NameLike Edge -Apply

    Only the profiles with 'Edge' in the name.

.EXAMPLE
    ./Add-GroupExclusion.ps1 -Group "Break-Glass Accounts" -Area Configuration,Compliance `
        -TenantId contoso.com -ClientId $appId -CertificateThumbprint $thumb -Apply

    Unattended runbook shape, across two areas.

.OUTPUTS
    The plan / result rows (Area, Resource, Status, Detail). Exit code 0 on
    success, 1 if any profile failed to write.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Group,
    [string[]]$Area = @('Configuration'),
    [string]$NameLike,
    [switch]$Apply,
    [string]$ReceiptPath,
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$CertificateThumbprint,
    [switch]$SkipConnect
)

$ErrorActionPreference = 'Stop'

# ── Load the module: next to this script first, then anything installed ───────
if (-not (Get-Module JustGraphIT)) {
    $local = Join-Path (Split-Path $PSScriptRoot -Parent) 'JustGraphIT.psd1'
    if (Test-Path $local) { Import-Module $local -Force }
    elseif (Get-Module JustGraphIT -ListAvailable) { Import-Module JustGraphIT -Force }
    else { throw "JustGraphIT not found. Run this from the module's examples folder, or install the module first." }
}

# ── Sign in (unless the caller already did) ──────────────────────────────────
if (-not $SkipConnect) {
    $ctx = try { Get-MgContext } catch { $null }
    if (-not $ctx -or $ClientId) {
        $p = @{}
        if ($TenantId)              { $p.TenantId              = $TenantId }
        if ($ClientId)              { $p.ClientId              = $ClientId }
        if ($ClientSecret)          { $p.ClientSecret          = $ClientSecret }
        if ($CertificateThumbprint) { $p.CertificateThumbprint = $CertificateThumbprint }
        Write-Host 'Connecting to Microsoft Graph…' -ForegroundColor DarkGray
        Connect-JustGraphIT @p | Out-Null
    }
}

# ── Resolve the group up front so a typo fails before any sweep ──────────────
$plan = @{ Group = $Group; Area = $Area; Exclude = $true }
if ($NameLike) { $plan.NameLike = $NameLike }
if ($Area -contains 'All') { $plan.Remove('Area') }

$scope = "area(s): $($Area -join ', ')" + $(if ($NameLike) { " · name contains '$NameLike'" })
Write-Host ""
Write-Host "Excluding group : $Group"           -ForegroundColor White
Write-Host "Scope           : $scope"           -ForegroundColor White
Write-Host "Mode            : $(if ($Apply) { 'APPLY (writes)' } else { 'PREVIEW (no writes)' })" `
    -ForegroundColor $(if ($Apply) { 'Yellow' } else { 'Cyan' })
Write-Host ""

# ── Plan (never writes) ──────────────────────────────────────────────────────
$rows = @(Add-IntuneBulkAssignment @plan -WhatIf)
if (-not $rows.Count) {
    Write-Host "Nothing matched that scope — no profiles to change." -ForegroundColor Yellow
    exit 0
}

$new     = @($rows | Where-Object { -not $_.Skipped })
$skipped = @($rows | Where-Object { $_.Skipped })

# Out-String, not a bare Format-Table: bare formatting renders NOTHING when stdout
# is redirected (a log file, an Azure Automation job) — only on a live terminal.
$rows | ForEach-Object {
    [pscustomobject]@{
        Area     = $_.Area
        Resource = $_.ResourceName
        Status   = if ($_.Skipped) { 'skip' } else { 'will exclude' }
        Detail   = if ($_.Skipped) { $_.Skipped } else { ($_.Added -join '; ') }
    }
} | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

Write-Host ("{0} profile(s) to change, {1} already excluded." -f $new.Count, $skipped.Count) -ForegroundColor White

if (-not $Apply) {
    Write-Host ""
    Write-Host "Preview only. Re-run with -Apply to write these changes." -ForegroundColor Cyan
    exit 0
}
if (-not $new.Count) {
    Write-Host "Every matching profile already excludes that group — nothing to do." -ForegroundColor Green
    exit 0
}

# ── Apply ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Writing…" -ForegroundColor Yellow
$results = @(Add-IntuneBulkAssignment @plan -Confirm:$false)

$applied = @($results | Where-Object Applied)
$failed  = @($results | Where-Object { $_.Error })

$results | ForEach-Object {
    [pscustomobject]@{
        Area     = $_.Area
        Resource = $_.ResourceName
        Status   = if ($_.Error) { 'FAILED' } elseif ($_.Applied) { 'ok' } else { 'skip' }
        Detail   = if ($_.Error) { $_.Error } elseif ($_.Skipped) { $_.Skipped } else { ($_.Added -join '; ') }
    }
} | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# ── Receipt for the change ticket ────────────────────────────────────────────
if (-not $ReceiptPath) {
    $ReceiptPath = Join-Path $PSScriptRoot ("exclusion-receipt-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
}
$results | Select-Object Area, ResourceType, ResourceName, ResourceId,
    @{ n = 'Change';  e = { $_.Added -join '; ' } },
    @{ n = 'Applied'; e = { $_.Applied } },
    @{ n = 'Skipped'; e = { $_.Skipped } },
    @{ n = 'Error';   e = { $_.Error } } |
    Export-Csv -Path $ReceiptPath -NoTypeInformation -Encoding utf8NoBOM

Write-Host ""
Write-Host ("Applied {0} · failed {1} · skipped {2}" -f $applied.Count, $failed.Count, @($results | Where-Object Skipped).Count) `
    -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
Write-Host "Receipt: $ReceiptPath" -ForegroundColor DarkGray

if ($failed.Count) {
    Write-Host ""
    Write-Host "Some profiles rejected the write. The usual cause is Intune refusing to mix" -ForegroundColor Yellow
    Write-Host "user groups and device groups in one profile's include/exclude set." -ForegroundColor Yellow
    exit 1
}
exit 0
