function Connect-JustGraphIT {
    <#
    .SYNOPSIS
        Sign in to Microsoft Graph for Intune assignment management.
    .DESCRIPTION
        Wraps Connect-MgGraph. Supports interactive sign-in, device code
        (great over SSH / for headless Macs), and app-only auth with a client
        secret or certificate. Runs anywhere pwsh + Microsoft.Graph.Authentication
        run (macOS, Windows, Linux).

        Bring your own app registration in any mode with -ClientId:
          - with -ClientSecret or -CertificateThumbprint → APP-ONLY; the token
            carries the app's granted APPLICATION permissions (the -Scopes list
            is not used — consent lives on the app registration).
          - alone (interactive/device code) → DELEGATED through your app instead
            of the Microsoft Graph command-line client; the app needs the
            delegated Graph permissions consented, plus a 'http://localhost'
            redirect URI (interactive) or 'Allow public client flows' (device code).
        Areas the identity lacks permission for fail per-report with a 403 and
        the rest of the module keeps working.
    .EXAMPLE
        Connect-JustGraphIT -UseDeviceCode
    .EXAMPLE
        Connect-JustGraphIT -TenantId contoso.com -ClientId <id> -ClientSecret <secret>
    .EXAMPLE
        Connect-JustGraphIT -TenantId contoso.com -ClientId <id> -CertificateThumbprint <thumb>

        App-only with your own app registration — the runbook shape.
    .EXAMPLE
        Connect-JustGraphIT -TenantId contoso.com -ClientId <id>

        Delegated sign-in through your own app registration.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [string]$TenantId,
        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$UseDeviceCode,
        [Parameter(ParameterSetName = 'Interactive')]
        [Parameter(ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'Secret', Mandatory)]
        [string]$ClientId,
        [Parameter(ParameterSetName = 'Secret', Mandatory)]
        [string]$ClientSecret,
        [Parameter(ParameterSetName = 'Certificate')]
        [string]$CertClientId,
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [string]$CertificateThumbprint,
        [string[]]$Scopes = @(
            'DeviceManagementConfiguration.ReadWrite.All',
            'DeviceManagementApps.ReadWrite.All',
            'DeviceManagementServiceConfig.ReadWrite.All',
            'DeviceManagementManagedDevices.Read.All',
            'CloudPC.ReadWrite.All',
            'Group.Read.All',
            'Directory.Read.All',
            'RoleManagementPolicy.Read.Directory',
            'RoleEligibilitySchedule.Read.Directory',
            'RoleAssignmentSchedule.ReadWrite.Directory',
            # --- Entra identity management (Phase 2+) ---
            'User.ReadWrite.All',
            'Group.ReadWrite.All',
            'GroupMember.ReadWrite.All',
            'UserAuthenticationMethod.ReadWrite.All',
            'Organization.Read.All',
            # --- Entra reporting / access / security ---
            'AuditLog.Read.All',
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'IdentityRiskyUser.ReadWrite.All',
            'IdentityRiskEvent.Read.All',
            'Application.Read.All',
            'RoleManagement.Read.Directory',
            'SecurityEvents.Read.All',
            'Reports.Read.All',
            'ConfigurationMonitoring.Read.All'
        )
    )

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication is required. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Secret' {
            $sec = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
            $cred = [System.Management.Automation.PSCredential]::new($ClientId, $sec)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome -ErrorAction Stop
        }
        'Certificate' {
            $cid = if ($ClientId) { $ClientId } else { $CertClientId }
            if (-not $cid) { throw 'Certificate auth needs the app registration id: pass -ClientId (or legacy -CertClientId).' }
            Connect-MgGraph -TenantId $TenantId -ClientId $cid -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
        }
        default {
            $p = @{ Scopes = $Scopes; NoWelcome = $true; ErrorAction = 'Stop' }
            if ($TenantId) { $p.TenantId = $TenantId }
            if ($ClientId) { $p.ClientId = $ClientId }
            if ($UseDeviceCode) { $p.UseDeviceCode = $true }
            Connect-MgGraph @p
        }
    }

    Reset-IaDirectoryCache
    $ctx = Get-MgContext
    [pscustomobject]@{
        TenantId = $ctx.TenantId
        Account  = $ctx.Account
        AppName  = $ctx.AppName
        Scopes   = ($ctx.Scopes -join ', ')
    }
}
