<#
.SYNOPSIS
    Run the JustGraphIT terminal UI offline with mock data — no tenant, no Microsoft.Graph
    module, no permissions required.

.DESCRIPTION
    Stubs the three Microsoft Graph entry points JustGraphIT uses (Get-MgContext,
    Connect-MgGraph, Invoke-MgGraphRequest) with a small in-memory fixture, imports the
    module from this repo, and launches the interactive UI. Everything you see is fake
    sample data, so you can click around every screen safely.

    To use JustGraphIT against a real tenant instead, skip this file:
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
        Import-Module ./JustGraphIT.psd1
        Connect-JustGraphIT        # interactive / device-code / app-only
        Start-JustGraphIT          # or the `jgi` alias

.EXAMPLE
    pwsh -NoProfile -File ./examples/Invoke-JustGraphITDemo.ps1
#>
[CmdletBinding()]
param([string]$Theme = 'deepsea')

$ErrorActionPreference = 'Continue'

# ── Mock Microsoft Graph (sample data only) ──────────────────────────────────
function global:Get-MgContext {
    [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = '11111111-2222-3333-4444-555555555555'
        Scopes = @('DeviceManagementApps.Read.All', 'DeviceManagementConfiguration.Read.All', 'DeviceManagementManagedDevices.Read.All') }
}
function global:Connect-MgGraph { param([Parameter(ValueFromRemainingArguments)]$a) }

function items($names, $nameField, [switch]$withAsg, $odatatype) {
    $i = 0
    $names | ForEach-Object {
        $i++
        $o = [ordered]@{ id = ('id-{0:D2}' -f $i) }
        $o[$nameField] = $_
        if ($odatatype) { $o['@odata.type'] = $odatatype }
        if ($withAsg) {
            $gid = @('g1', 'g2', 'g3')[$i % 3]
            $o['assignments'] = @([pscustomobject]@{ id = "a$i"; target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $gid } })
        } else { $o['assignments'] = @() }
        [pscustomobject]$o
    }
}
function page($v) { [pscustomobject]@{ value = @($v); '@odata.nextLink' = $null } }

function global:Invoke-MgGraphRequest {
    param($Method, $Uri, $Body, $Headers, $OutputType, $ContentType, $ErrorAction)
    # The module URL-encodes $filter values; decode so the fixture regexes below
    # (e.g. "deviceName eq 'X'") match the way they read.
    $u = [uri]::UnescapeDataString([string]$Uri)
    if ($u -match '/assignments(\?|$)') { return page @() }
    if ($u -match 'assignmentFilters') { return page (items @('Corporate Windows', 'Personal iOS', 'macOS Lab') 'displayName') }
    if ($u -match '/groups/(g\d)') {
        $nm = @{ g1 = 'All Pilot Devices'; g2 = 'Finance Users'; g3 = 'HR Department' }[$Matches[1]]
        return [pscustomobject]@{ id = $Matches[1]; displayName = $nm; membershipRule = $null }
    }
    if ($u -match "groups\?.*displayName eq '([^']+)'") {
        # Honour the filter: known demo groups resolve, anything else is genuinely
        # not-found (so create-on-first-run paths like Sync-IntuneDiscoveredAppGroup work).
        $want = $Matches[1]
        $known = @(
            [pscustomobject]@{ id = 'g1'; displayName = 'All Pilot Devices' }
            [pscustomobject]@{ id = 'g2'; displayName = 'Finance Users' }
            [pscustomobject]@{ id = 'g3'; displayName = 'HR Department' })
        return page @($known | Where-Object { $_.displayName -eq $want })
    }
    if ($u -match '/groups(\?|$|/)') { return page @(
        [pscustomobject]@{ id = 'g1'; displayName = 'All Pilot Devices' }
        [pscustomobject]@{ id = 'g2'; displayName = 'Finance Users' }
        [pscustomobject]@{ id = 'g3'; displayName = 'HR Department' }) }
    if ($u -match 'configurationPolicies') { return page (items @('Win11 Security Baseline', 'Edge Hardening', 'BitLocker Silent Encryption', 'Defender ASR Rules', 'Wi-Fi Corporate', 'OneDrive KFM') 'name' -withAsg) }
    if ($u -match 'deviceCompliancePolicies') { return page (items @('Windows Compliance', 'macOS Compliance', 'iOS Compliance', 'Android Compliance') 'displayName' -withAsg) }
    if ($u -match 'deviceConfigurations(\?|/|$)') { return page (items @('macOS FileVault', 'iOS Restrictions', 'Windows Health Monitoring', 'Domain Join') 'displayName' -withAsg) }
    if ($u -match 'deviceHealthScripts') { return page (items @('Restart Stuck Spooler', 'Clear Temp Files', 'BitLocker Key Rotation', 'Disk Cleanup') 'displayName') }
    if ($u -match 'deviceManagementScripts') { return page (items @('Map Network Drives', 'Install Corp Fonts') 'displayName') }
    if ($u -match 'mobileApps') { return page (items @('Microsoft 365 Apps', 'Company Portal', 'Google Chrome', 'Slack', 'Zoom', 'Adobe Reader') 'displayName' -withAsg '#microsoft.graph.win32LobApp') }
    if ($u -match 'windows(Feature|Quality|Driver)UpdateProfiles') { return page (items @('Ring 1 — Pilot', 'Ring 2 — Broad', 'Ring 3 — Critical') 'displayName' -withAsg) }
    if ($u -match '/me(\?|$)') { return [pscustomobject]@{ id = 'u-admin'; userPrincipalName = 'admin@contoso.com'; displayName = 'Admin' } }
    if ($u -match 'mobileAppIntentAndStates') { return [pscustomobject]@{ mobileAppList = @(
        [pscustomobject]@{ displayName = 'Microsoft 365 Apps'; mobileAppIntent = 'required'; installState = 'installed'; displayVersion = '16.0.17328' }
        [pscustomobject]@{ displayName = 'Company Portal'; mobileAppIntent = 'required'; installState = 'installed'; displayVersion = '5.0.6094' }
        [pscustomobject]@{ displayName = 'Google Chrome'; mobileAppIntent = 'available'; installState = 'installed'; displayVersion = '126.0.6478' }
        [pscustomobject]@{ displayName = 'Adobe Acrobat Reader'; mobileAppIntent = 'available'; installState = 'failed'; displayVersion = '2024.002.20933' }
        [pscustomobject]@{ displayName = 'Slack'; mobileAppIntent = 'available'; installState = 'notInstalled'; displayVersion = '' }) } }
    if ($u -match '/users/[^/?]+/transitiveMemberOf') { return page @(
        [pscustomobject]@{ id = 'g2'; displayName = 'Finance Users'; securityEnabled = $true; mailEnabled = $false; groupTypes = @(); membershipRule = $null }
        [pscustomobject]@{ id = 'g4'; displayName = 'All Staff'; securityEnabled = $false; mailEnabled = $true; groupTypes = @('Unified'); membershipRule = $null }
        [pscustomobject]@{ id = 'g5'; displayName = 'Pilot Ring 1'; securityEnabled = $true; mailEnabled = $false; groupTypes = @(); membershipRule = '(user.department -eq "IT")' }) }
    if ($u -match '/licenseDetails') { return page @(
        [pscustomobject]@{ id = 'lic1'; skuId = 'c7df2760-2c81-4ef7-b578-5b5392b571df'; skuPartNumber = 'SPE_E5'; servicePlans = @(
            [pscustomobject]@{ servicePlanName = 'TEAMS1'; provisioningStatus = 'Success' }
            [pscustomobject]@{ servicePlanName = 'EXCHANGE_S_ENTERPRISE'; provisioningStatus = 'Success' }
            [pscustomobject]@{ servicePlanName = 'INTUNE_A'; provisioningStatus = 'Success' }
            [pscustomobject]@{ servicePlanName = 'MCOEV'; provisioningStatus = 'PendingProvisioning' }) }
        [pscustomobject]@{ id = 'lic2'; skuId = 'b05e124f-c7cc-45a0-a6aa-8cf78c946968'; skuPartNumber = 'EMSPREMIUM'; servicePlans = @(
            [pscustomobject]@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }
            [pscustomobject]@{ servicePlanName = 'INTUNE_A'; provisioningStatus = 'Success' }) }
        [pscustomobject]@{ id = 'lic3'; skuId = 'f8a1db68-be16-40ed-86d5-cb42ce701560'; skuPartNumber = 'POWER_BI_PRO'; servicePlans = @(
            [pscustomobject]@{ servicePlanName = 'BI_AZURE_P2'; provisioningStatus = 'Success' }) }) }
    if ($u -match '/authentication/methods') { return page @(
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'; id = 'm1'; displayName = 'Pixel 8 Pro' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod'; id = 'm2'; phoneNumber = '+1 206 555 0142'; phoneType = 'mobile' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'; id = 'm3'; displayName = 'LAPTOP-01' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod'; id = 'm4' }) }
    if ($u -match 'auditLogs/signIns') { return page @(
        [pscustomobject]@{ createdDateTime = '2026-06-27T08:15:00Z'; appDisplayName = 'Microsoft Teams'; ipAddress = '203.0.113.5'; clientAppUsed = 'Browser'; conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = 0; failureReason = 'Other.' }; deviceDetail = [pscustomobject]@{ displayName = 'LAPTOP-01' }; appliedConditionalAccessPolicies = @() }
        [pscustomobject]@{ createdDateTime = '2026-06-27T07:50:00Z'; appDisplayName = 'Office 365 Exchange Online'; ipAddress = '198.51.100.9'; clientAppUsed = 'Mobile Apps and Desktop clients'; conditionalAccessStatus = 'failure'; status = [pscustomobject]@{ errorCode = 53003; failureReason = 'Access blocked by Conditional Access policies.' }; deviceDetail = [pscustomobject]@{ displayName = '' }; appliedConditionalAccessPolicies = @([pscustomobject]@{ displayName = 'Require compliant device'; result = 'failure' }) }
        [pscustomobject]@{ createdDateTime = '2026-06-26T22:10:00Z'; appDisplayName = 'Microsoft Authenticator'; ipAddress = '198.51.100.9'; clientAppUsed = 'Mobile Apps and Desktop clients'; conditionalAccessStatus = 'notApplied'; status = [pscustomobject]@{ errorCode = 50074; failureReason = 'Strong authentication is required.' }; deviceDetail = [pscustomobject]@{ displayName = '' }; appliedConditionalAccessPolicies = @() }
        [pscustomobject]@{ createdDateTime = '2026-06-26T09:00:00Z'; appDisplayName = 'Windows Sign In'; ipAddress = '203.0.113.5'; clientAppUsed = 'Browser'; conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = 0; failureReason = 'Other.' }; deviceDetail = [pscustomobject]@{ displayName = 'LAPTOP-01' }; appliedConditionalAccessPolicies = @() }) }
    if ($u -match 'deviceCompliancePolicyStates') { return page @(
        [pscustomobject]@{ id = 'cps1'; displayName = 'Windows 11 Compliance'; state = 'nonCompliant'; platformType = 'windows10AndLater'; settingStates = @(
            [pscustomobject]@{ setting = 'DefaultDeviceCompliancePolicy.bitLockerEnabled'; settingName = 'BitLocker encryption'; state = 'nonCompliant'; currentValue = 'NotEncrypted'; errorCode = 0; errorDescription = '' }
            [pscustomobject]@{ setting = 'DefaultDeviceCompliancePolicy.osMinimumVersion'; settingName = 'Minimum OS version'; state = 'nonCompliant'; currentValue = '10.0.19045'; errorCode = 0; errorDescription = 'Below required 10.0.22000' }
            [pscustomobject]@{ setting = 'DefaultDeviceCompliancePolicy.passwordRequired'; settingName = 'Password required'; state = 'compliant'; currentValue = 'True'; errorCode = 0; errorDescription = '' }) }
        [pscustomobject]@{ id = 'cps2'; displayName = 'Default Device Compliance'; state = 'compliant'; platformType = 'windows10AndLater'; settingStates = @(
            [pscustomobject]@{ setting = 'DefaultDeviceCompliancePolicy.passwordRequired'; settingName = 'Password required'; state = 'compliant'; currentValue = 'True'; errorCode = 0; errorDescription = '' }) }) }
    if ($u -match 'deviceConfigurationStates') { return page @(
        [pscustomobject]@{ id = 'cfs1'; displayName = 'Edge Hardening'; state = 'conflict'; settingStates = @(
            [pscustomobject]@{ setting = 'edge.homepageLocation'; settingName = 'Edge — home page URL'; state = 'conflict'; currentValue = '(conflicting values)'; sources = @(
                [pscustomobject]@{ id = 'p1'; displayName = 'Edge Hardening' }
                [pscustomobject]@{ id = 'p2'; displayName = 'Edge Baseline (legacy)' }) }
            [pscustomobject]@{ setting = 'power.sleepTimeout'; settingName = 'Sleep timeout'; state = 'compliant'; currentValue = '15'; sources = @() }) }
        [pscustomobject]@{ id = 'cfs2'; displayName = 'Wi-Fi Corporate'; state = 'compliant'; settingStates = @() }) }
    if ($u -match 'users/\$count') { if ($u -match "userType eq 'Guest'") { return 0 }; return 4 }
    if ($u -match '/users/') { return [pscustomobject]@{ id = 'u-alice'; displayName = 'Alice Anderson'; userPrincipalName = 'alice@contoso.com' } }
    if ($u -match 'roleEligibilityScheduleInstances') { return page @(
        [pscustomobject]@{ roleDefinitionId = 'r1'; directoryScopeId = '/'; memberType = 'Direct'; endDateTime = $null; roleDefinition = [pscustomobject]@{ displayName = 'Intune Administrator' } }
        [pscustomobject]@{ roleDefinitionId = 'r2'; directoryScopeId = '/'; memberType = 'Group'; endDateTime = $null; roleDefinition = [pscustomobject]@{ displayName = 'Cloud Device Administrator' } }
        [pscustomobject]@{ roleDefinitionId = 'r3'; directoryScopeId = '/'; memberType = 'Direct'; endDateTime = $null; roleDefinition = [pscustomobject]@{ displayName = 'Security Reader' } }) }
    if ($u -match 'roleAssignmentScheduleInstances') { return page @(
        [pscustomobject]@{ roleDefinitionId = 'r1'; directoryScopeId = '/'; memberType = 'Direct'; endDateTime = '2026-06-27T18:00:00Z'; roleDefinition = [pscustomobject]@{ displayName = 'Intune Administrator' } }) }
    if ($u -match 'windowsAutopilotDeviceIdentities') { return page @(
        [pscustomobject]@{ id = 'ap1'; serialNumber = 'SN-AP-001'; manufacturer = 'Dell'; model = 'Latitude 7440'; groupTag = 'Corp-Standard'; enrollmentState = 'enrolled'; deploymentProfileAssignmentStatus = 'assignedAndDeployed'; azureActiveDirectoryDeviceId = 'aad-0001' }
        [pscustomobject]@{ id = 'ap2'; serialNumber = 'SN-AP-002'; manufacturer = 'Lenovo'; model = 'ThinkPad X1'; groupTag = 'Corp-Standard'; enrollmentState = 'notContacted'; deploymentProfileAssignmentStatus = 'assignedOutOfSync'; azureActiveDirectoryDeviceId = '' }
        [pscustomobject]@{ id = 'ap3'; serialNumber = 'SN-AP-003'; manufacturer = 'HP'; model = 'EliteBook 840'; groupTag = 'Kiosk'; enrollmentState = 'enrolled'; deploymentProfileAssignmentStatus = 'assignedAndDeployed'; azureActiveDirectoryDeviceId = 'aad-0009' }) }
    if ($u -match 'windowsAutopilotDeploymentProfiles') { return page (items @('Corp Standard (user-driven)', 'Kiosk (self-deploying)', 'Pre-provisioned') 'displayName' -withAsg) }
    if ($u -match 'bitlocker/recoveryKeys/[^/?]+\?') { return [pscustomobject]@{ key = '482119-208510-114393-072018-660129-501774-329841-220155' } }
    if ($u -match 'bitlocker/recoveryKeys') { return page @(
        [pscustomobject]@{ id = 'bk1'; createdDateTime = '2026-05-01T10:00:00Z'; volumeType = 'operatingSystemVolume'; deviceId = 'aad-0001' }
        [pscustomobject]@{ id = 'bk2'; createdDateTime = '2026-06-15T10:00:00Z'; volumeType = 'fixedDataVolume'; deviceId = 'aad-0001' }) }
    if ($u -match 'deviceLocalCredentials/') { return [pscustomobject]@{ credentials = @(
        [pscustomobject]@{ accountName = 'Administrator'; accountSid = 'S-1-5-21-1602...-500'; backupDateTime = '2026-06-26T03:00:00Z'; passwordBase64 = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('jG!t-L0cal#Adm-7vQ2pX'))) }
        [pscustomobject]@{ accountName = 'Administrator'; accountSid = 'S-1-5-21-1602...-500'; backupDateTime = '2026-05-26T03:00:00Z'; passwordBase64 = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Old-Rotated#2026-05'))) }) } }
    if ($u -match 'virtualEndpoint/reports/') { return [pscustomobject]@{
        totalRowCount = 3
        schema        = @(
            [pscustomobject]@{ column = 'CloudPcName' }
            [pscustomobject]@{ column = 'UserPrincipalName' }
            [pscustomobject]@{ column = 'TotalUsageInHour' }
            [pscustomobject]@{ column = 'RemoteConnectionCount' }
            [pscustomobject]@{ column = 'LastActiveTime' }
        )
        values        = @(
            , @('CPC-Alice', 'alice@contoso.com', 142.5, 88, '2026-06-26T09:00:00Z')
            , @('CPC-Bob', 'bob@contoso.com', 67.2, 41, '2026-06-25T14:00:00Z')
            , @('CPC-Carol', 'carol@contoso.com', 11.0, 9, '2026-06-20T08:00:00Z')
        ) } }
    if ($u -match 'virtualEndpoint/cloudPCs') { return page @(
        [pscustomobject]@{ id = 'cpc1'; displayName = 'CPC-Alice'; status = 'provisioned'; userPrincipalName = 'alice@contoso.com'; servicePlanName = 'Enterprise 2vCPU/8GB/128GB'; provisioningPolicyName = 'Finance Cloud PCs'; deviceRegionName = 'westus2'; lastLoginResult = [pscustomobject]@{ time = '2026-06-26T09:00:00Z' } }
        [pscustomobject]@{ id = 'cpc2'; displayName = 'CPC-Bob'; status = 'provisioned'; userPrincipalName = 'bob@contoso.com'; servicePlanName = 'Enterprise 4vCPU/16GB/256GB'; provisioningPolicyName = 'Engineering Cloud PCs'; deviceRegionName = 'eastus'; lastLoginResult = [pscustomobject]@{ time = '2026-06-25T14:00:00Z' } }
        [pscustomobject]@{ id = 'cpc3'; displayName = 'CPC-Carol'; status = 'inGracePeriod'; userPrincipalName = 'carol@contoso.com'; servicePlanName = 'Enterprise 2vCPU/8GB/128GB'; provisioningPolicyName = 'Finance Cloud PCs'; deviceRegionName = 'westus2'; gracePeriodEndDateTime = '2026-07-01T00:00:00Z'; lastLoginResult = [pscustomobject]@{ time = '2026-06-20T08:00:00Z' } }) }
    if ($u -match 'userRegistrationDetails') { return page @(
        [pscustomobject]@{ id = 'u-alice'; userDisplayName = 'Alice Anderson'; userPrincipalName = 'alice@contoso.com'; isAdmin = $true;  isMfaRegistered = $true;  isMfaCapable = $true;  isSsprRegistered = $true;  isSsprCapable = $true;  methodsRegistered = @('microsoftAuthenticatorPush','windowsHelloForBusiness'); defaultMfaMethod = 'microsoftAuthenticatorPush'; userType = 'member' }
        [pscustomobject]@{ id = 'u-bob';   userDisplayName = 'Bob Brown';      userPrincipalName = 'bob@contoso.com';   isAdmin = $false; isMfaRegistered = $false; isMfaCapable = $false; isSsprRegistered = $false; isSsprCapable = $false; methodsRegistered = @();                                             defaultMfaMethod = $null;                        userType = 'member' }
        [pscustomobject]@{ id = 'u-carol'; userDisplayName = 'Carol Chen';     userPrincipalName = 'carol@contoso.com'; isAdmin = $false; isMfaRegistered = $true;  isMfaCapable = $true;  isSsprRegistered = $true;  isSsprCapable = $true;  methodsRegistered = @('softwareOneTimePasscode');                    defaultMfaMethod = 'softwareOneTimePasscode';    userType = 'member' }
        [pscustomobject]@{ id = 'u-dave';  userDisplayName = 'Dave Diaz';      userPrincipalName = 'dave@contoso.com';  isAdmin = $true;  isMfaRegistered = $true;  isMfaCapable = $false; isSsprRegistered = $false; isSsprCapable = $false; methodsRegistered = @('phone');                                      defaultMfaMethod = $null;                        userType = 'member' }) }
    if ($u -match 'applePushNotificationCertificate') { return [pscustomobject]@{ appleIdentifier = 'mdm@contoso.com'; expirationDateTime = (Get-Date).AddDays(12).ToUniversalTime().ToString('o') } }
    if ($u -match 'vppTokens') { return page @([pscustomobject]@{ id = 'vpp1'; appleId = 'vpp@contoso.com'; state = 'valid'; lastSyncStatus = 'completed'; expirationDateTime = (Get-Date).AddDays(200).ToUniversalTime().ToString('o') }) }
    if ($u -match 'depOnboardingSettings') { return page @([pscustomobject]@{ id = 'dep1'; appleIdentifier = 'ade@contoso.com'; tokenExpirationDateTime = (Get-Date).AddDays(45).ToUniversalTime().ToString('o') }) }
    if ($u -match 'androidManagedStoreAccountEnterpriseSettings') { return [pscustomobject]@{ bindStatus = 'notBound' } }
    if ($u -match 'ndesConnectors') { return page @([pscustomobject]@{ id = 'ndes1'; displayName = 'NDES-01'; state = 'active'; lastConnectionDateTime = (Get-Date).AddHours(-3).ToUniversalTime().ToString('o') }) }
    if ($u -match 'configurationMonitoringResults') { return page @(
        [pscustomobject]@{ id = 'run1'; monitorId = 'cm1'; runStatus = 'successful'; driftsCount = 1; runInitiationDateTime = (Get-Date).AddHours(-7).ToUniversalTime().ToString('o'); runCompletionDateTime = (Get-Date).AddHours(-7).AddMinutes(4).ToUniversalTime().ToString('o'); errorDetails = @() }) }
    if ($u -match 'configurationDrifts') { return page @(
        [pscustomobject]@{ id = 'cd1'; monitorId = 'cm1'; baselineResourceDisplayName = 'Require MFA for admins'; resourceType = 'conditionalAccessPolicy'; status = 'active'; firstReportedDateTime = '2026-06-26T21:10:00Z'; resourceInstanceIdentifier = [pscustomobject]@{ policyId = 'ca-101' }; driftedProperties = @(
            [pscustomobject]@{ propertyName = 'state'; desiredValue = 'enabled'; currentValue = 'disabled' }) }
        [pscustomobject]@{ id = 'cd2'; monitorId = 'cm1'; baselineResourceDisplayName = 'Named location: HQ egress'; resourceType = 'namedLocation'; status = 'fixed'; firstReportedDateTime = '2026-06-20T09:00:00Z'; resourceInstanceIdentifier = [pscustomobject]@{ locationId = 'nl-7' }; driftedProperties = @(
            [pscustomobject]@{ propertyName = 'ipRanges'; desiredValue = @('203.0.113.0/24'); currentValue = @('203.0.113.0/24', '198.51.100.0/24') }) }) }
    if ($u -match 'configurationMonitors') { return page @(
        [pscustomobject]@{ id = 'cm1'; displayName = 'Conditional Access baseline'; description = 'Prod CA posture'; mode = 'monitorOnly'; status = 'active'; monitorRunFrequencyInHours = 24; createdDateTime = '2026-05-01T12:00:00Z'; lastModifiedDateTime = '2026-06-01T12:00:00Z'; createdBy = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Alice Anderson' } }; lastModifiedBy = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Alice Anderson' } }; baseline = [pscustomobject]@{ displayName = 'CA baseline'; description = 'Prod CA posture'; resources = @(
            [pscustomobject]@{ displayName = 'Require MFA for admins'; resourceType = 'conditionalAccessPolicy'; properties = $null }
            [pscustomobject]@{ displayName = 'Named location: HQ egress'; resourceType = 'namedLocation'; properties = $null }) } }) }
    # (informationProtection/bitlocker/recoveryKeys is served by the earlier
    #  'bitlocker/recoveryKeys' matcher above — keys escrowed for aad-0001 only.)
    if ($u -match 'detectedApps/[^/?]+/managedDevices') { return page @(
        [pscustomobject]@{ id = 'd1'; deviceName = 'LAPTOP-01';  userPrincipalName = 'alice@contoso.com'; emailAddress = 'alice@contoso.com'; operatingSystem = 'Windows'; azureADDeviceId = 'aad-0001' }
        [pscustomobject]@{ id = 'd2'; deviceName = 'LAPTOP-02';  userPrincipalName = 'bob@contoso.com';   emailAddress = 'bob@contoso.com';   operatingSystem = 'Windows'; azureADDeviceId = 'aad-0002' }
        [pscustomobject]@{ id = 'd4'; deviceName = 'CPC-12345';  userPrincipalName = 'dave@contoso.com';  emailAddress = 'dave@contoso.com';  operatingSystem = 'Windows'; azureADDeviceId = 'aad-0004' }) }
    if ($u -match 'deviceManagement/detectedApps') {
        $apps = @(
            [pscustomobject]@{ id = 'da1'; displayName = 'Zscaler Client Connector'; version = '4.3.2.157';   publisher = 'Zscaler Inc.';  platform = 'windows'; deviceCount = 3 }
            [pscustomobject]@{ id = 'da2'; displayName = 'Zscaler Client Connector'; version = '4.2.1.90';    publisher = 'Zscaler Inc.';  platform = 'windows'; deviceCount = 1 }
            [pscustomobject]@{ id = 'da3'; displayName = 'Google Chrome';            version = '126.0.6478';  publisher = 'Google LLC';    platform = 'windows'; deviceCount = 4 }
            [pscustomobject]@{ id = 'da4'; displayName = 'Slack';                    version = '4.39.90';     publisher = 'Slack';         platform = 'macOS';   deviceCount = 2 })
        if ($u -match "contains\(displayName,'([^']+)'\)") { $needle = $Matches[1]; $apps = @($apps | Where-Object { $_.displayName -like "*$needle*" }) }
        return page $apps
    }
    if ($u -match 'managedDevices/[^/?]+\?\$select=hardwareInformation') { return [pscustomobject]@{ hardwareInformation = [pscustomobject]@{ ipAddressV4 = '10.2.14.88'; serialNumber = 'SN002'; wifiMac = 'AA:BB:CC:DD:EE:FF' } } }
    if ($u -match 'managedDevices') {
        $devs = @(
            [pscustomobject]@{ id = 'd1'; deviceName = 'LAPTOP-01'; operatingSystem = 'Windows'; osVersion = '10.0.22631'; complianceState = 'compliant'; managedDeviceOwnerType = 'company'; lastSyncDateTime = '2026-06-25T10:00:00Z'; userId = 'u-alice'; userDisplayName = 'Alice'; userPrincipalName = 'alice@contoso.com'; emailAddress = 'alice@contoso.com'; manufacturer = 'Dell'; model = 'Latitude 7440'; serialNumber = 'SN001'; isEncrypted = $true; managementAgent = 'mdm'; deviceEnrollmentType = 'windowsAzureADJoin'; joinType = 'azureADJoined'; deviceType = 'windowsRT'; azureADDeviceId = 'aad-0001'; totalStorageSpaceInBytes = 512000000000; freeStorageSpaceInBytes = 210000000000 }
            [pscustomobject]@{ id = 'd2'; deviceName = 'LAPTOP-02'; operatingSystem = 'Windows'; osVersion = '10.0.22631'; complianceState = 'noncompliant'; managedDeviceOwnerType = 'company'; lastSyncDateTime = '2026-05-01T10:00:00Z'; userId = 'u-bob'; userDisplayName = 'Bob'; userPrincipalName = 'bob@contoso.com'; emailAddress = 'bob@contoso.com'; manufacturer = 'Lenovo'; model = 'ThinkPad X1'; serialNumber = 'SN002'; isEncrypted = $false; managementAgent = 'mdm'; deviceEnrollmentType = 'windowsAutoEnrollment'; joinType = 'azureADJoined'; deviceType = 'windowsRT'; azureADDeviceId = 'aad-0002'; totalStorageSpaceInBytes = 256000000000; freeStorageSpaceInBytes = 64000000000 }
            [pscustomobject]@{ id = 'd3'; deviceName = 'MACBOOK-01'; operatingSystem = 'macOS'; osVersion = '14.5'; complianceState = 'compliant'; managedDeviceOwnerType = 'personal'; lastSyncDateTime = '2026-06-26T08:00:00Z'; userId = 'u-carol'; userDisplayName = 'Carol'; userPrincipalName = 'carol@contoso.com'; emailAddress = 'carol@contoso.com'; manufacturer = 'Apple'; model = 'MacBook Pro'; serialNumber = 'SN003'; isEncrypted = $true; managementAgent = 'mdm'; deviceEnrollmentType = 'appleUserEnrollment'; joinType = 'workplaceJoined'; deviceType = 'macMDM'; azureADDeviceId = 'aad-0003'; totalStorageSpaceInBytes = 1000000000000; freeStorageSpaceInBytes = 540000000000 }
            [pscustomobject]@{ id = 'd4'; deviceName = 'CPC-12345'; operatingSystem = 'Windows'; osVersion = '10.0.22631'; complianceState = 'compliant'; managedDeviceOwnerType = 'company'; lastSyncDateTime = '2026-06-26T09:00:00Z'; userId = 'u-dave'; userDisplayName = 'Dave'; userPrincipalName = 'dave@contoso.com'; emailAddress = 'dave@contoso.com'; manufacturer = 'Microsoft'; model = 'Cloud PC'; serialNumber = 'SN004'; isEncrypted = $true; managementAgent = 'mdm'; deviceEnrollmentType = 'windowsAzureADJoin'; joinType = 'azureADJoined'; deviceType = 'cloudPC'; azureADDeviceId = 'aad-0004'; totalStorageSpaceInBytes = 128000000000; freeStorageSpaceInBytes = 96000000000 })
        if ($u -match '/managedDevices/(d\d)') { return ($devs | Where-Object { $_.id -eq $Matches[1] } | Select-Object -First 1) }
        if ($u -match "deviceName eq '([^']+)'") { $devs = @($devs | Where-Object { $_.deviceName -eq $Matches[1] }) }
        if ($u -match "userPrincipalName eq '([^']+)'") { $devs = @($devs | Where-Object { $_.userPrincipalName -eq $Matches[1] }) }
        return page $devs
    }
    if ($u -match '/devices/[^/?]+/transitiveMemberOf') { return page @(
        [pscustomobject]@{ id = 'g1'; displayName = 'All Pilot Devices'; membershipRule = $null }
        [pscustomobject]@{ id = 'g2'; displayName = 'Windows Autopilot Devices'; membershipRule = '(device.devicePhysicalIds -any (_ -contains "[ZTDId]"))' }
        [pscustomobject]@{ id = 'g3'; displayName = 'Finance Devices'; membershipRule = '(device.deviceOSType -eq "Windows")' }) }
    if ($u -match "/devices\?.*deviceId eq '([^']+)'") { return page @([pscustomobject]@{ id = "devobj-$($Matches[1])" }) }
    if ($u -match '/devices\?\$filter=displayName') { if ($u -match "displayName eq '([^']+)'") { return page @([pscustomobject]@{ id = 'devobj-1'; displayName = $Matches[1] }) }; return page @() }
    if ($u -match '\$select=id|/intents|provisioningPolicies|enrollmentConfigurations') { return page (items @('Sample Item One', 'Sample Item Two', 'Sample Item Three') 'displayName' -withAsg) }
    return page @()
}

# ── Import the module from this repo and launch the UI ───────────────────────
$manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'JustGraphIT.psd1'
Import-Module $manifest -Force

Write-Host ''
Write-Host '  ≈ JustGraphIT — offline demo' -ForegroundColor Cyan
Write-Host '  Sample/mock data only — nothing here touches a real tenant.' -ForegroundColor DarkGray
Write-Host '  Arrow keys / Enter to navigate · q or Esc to go back · Quit from the main menu.' -ForegroundColor DarkGray
Write-Host ''
Start-Sleep -Milliseconds 700

try { Start-JustGraphIT -Theme $Theme }
catch { Write-Host "Demo error: $($_.Exception.Message)" -ForegroundColor Red; Write-Host $_.ScriptStackTrace }
