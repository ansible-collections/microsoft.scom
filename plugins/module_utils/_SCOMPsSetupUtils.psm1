# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

Function Import-SCOMPsModule {
    <#
    .SYNOPSIS
    Imports the OperationsManager PowerShell module required for SCOM management.

    .DESCRIPTION
    Attempts to import the modern OperationsManager module (SCOM 2019+). If not found,
    falls back to the legacy Microsoft.EnterpriseManagement PSSnapin set (SCOM 2012/2016).

    REQUIREMENT: The OperationsManager module is only available on hosts where the SCOM
    Operations Console has been installed. This module will fail on any Windows host that
    does not have the SCOM Operations Console or SCOM SDK installed.

    Fails with a descriptive FailJson error if neither the module nor the legacy snap-ins
    are found, directing the operator to install the SCOM Operations Console.

    .PARAMETER module
    The Ansible module object used for error reporting via FailJson.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module
    )

    $modern_module = Get-Module -Name OperationsManager -ListAvailable
    if ($null -ne $modern_module) {
        Import-Module -Name OperationsManager -ErrorAction Stop
        return
    }

    $core_snapin = "Microsoft.EnterpriseManagement.Core.Cmdlets"
    $monitoring_snapin = "Microsoft.EnterpriseManagement.Monitoring.Cmdlets"

    $core_registered = Get-PSSnapin -Name $core_snapin -Registered -ErrorAction SilentlyContinue
    $monitoring_registered = Get-PSSnapin -Name $monitoring_snapin -Registered -ErrorAction SilentlyContinue

    if ($null -ne $core_registered -and $null -ne $monitoring_registered) {
        Add-PSSnapin -Name $core_snapin -ErrorAction Stop
        Add-PSSnapin -Name $monitoring_snapin -ErrorAction Stop
        return
    }

    $module.FailJson(
        "The OperationsManager PowerShell module is not present on this host. " +
        "Install the SCOM Operations Console or SCOM SDK components to provide the required module. " +
        "Supported versions: SCOM 2012 R2, 2016, 2019, 2022."
    )
}


Function Connect-SCOMManagementGroup {
    <#
    .SYNOPSIS
    Validates the auto-established SCOM Management Group connection and checks RBAC access.

    .DESCRIPTION
    This collection requires modules to run directly on the SCOM Management Server via WinRM.
    When Import-SCOMPsModule loads the OperationsManager module on the SCOM server, the SDK
    automatically connects to the local Management Group. This function verifies that
    auto-connection is active and that the executing account has at minimum the SCOM Operators
    role. Calls FailJson if the connection is not active or permissions are insufficient.

    .PARAMETER Module
    The Ansible module object used for error reporting via FailJson.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$Module
    )

    $mg = $null
    try {
        $mg = Get-SCOMManagementGroup -ErrorAction Stop
    }
    catch {
        $Module.FailJson(
            "No active SCOM Management Group connection found. " +
            "Ensure this module runs directly on the SCOM Management Server via WinRM. " +
            "Error: $($_.Exception.Message)"
        )
    }

    if ($null -eq $mg) {
        $Module.FailJson(
            "The OperationsManager module loaded but did not auto-connect to a Management Group. " +
            "Ensure this module runs directly on the SCOM Management Server via WinRM."
        )
    }

    try {
        $user_roles = Get-SCOMUserRole -ErrorAction Stop
        if ($null -eq $user_roles -or $user_roles.Count -eq 0) {
            $Module.FailJson(
                "The account running this module has no SCOM role assignments on management group '$($mg.Name)'. " +
                "Assign at minimum the SCOM Operators role."
            )
        }
    }
    catch [System.UnauthorizedAccessException] {
        $Module.FailJson(
            "Insufficient permissions on SCOM management group '$($mg.Name)'. " +
            "The account requires at minimum the SCOM Operators role: $($_.Exception.Message)"
        )
    }
    catch {
        $Module.Warn(
            "Could not verify SCOM role assignments (Get-SCOMUserRole failed): $($_.Exception.Message). " +
            "Proceeding — ensure the account has the required SCOM role."
        )
    }
}


Function ConvertTo-SCOMSeverityString {
    <#
    .SYNOPSIS
    Converts a SCOM MonitoringAlertSeverity integer value to a human-readable string.

    .PARAMETER SeverityValue
    The integer severity value returned from a SCOM alert object.
    0 = Information, 1 = Warning, 2 = Critical.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$SeverityValue
    )

    switch ([int]$SeverityValue) {
        0 { return "information" }
        1 { return "warning" }
        2 { return "critical" }
    }

    return "unknown"
}


Function ConvertTo-SCOMResolutionStateString {
    <#
    .SYNOPSIS
    Converts a SCOM alert resolution state integer to a human-readable label.

    .DESCRIPTION
    SCOM reserves state 0 (New) and 255 (Closed). States 1-254 are customizable
    per management group. This function maps the well-known values and returns
    "custom_<value>" for any non-standard states, allowing callers to handle them.

    .PARAMETER ResolutionState
    The integer resolution state from a SCOM alert object.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$ResolutionState
    )

    switch ([int]$ResolutionState) {
        0 { return "new" }
        255 { return "closed" }
        default { return "custom_$ResolutionState" }
    }
}


Function Format-DateTimeAsStringSafely {
    <#
    .SYNOPSIS
    Formats a DateTime object as a string, returning an empty string for null input.

    .PARAMETER dateTimeObject
    The DateTime object to format. Accepts null.

    .PARAMETER format
    Optional .NET DateTime format string. Defaults to "yyyy-MM-dd HH:mm:ss z".
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$dateTimeObject,
        [Parameter(Mandatory = $false)][string]$format = "yyyy-MM-dd HH:mm:ss z"
    )

    if ($null -eq $dateTimeObject) {
        return ""
    }

    try {
        return $dateTimeObject.ToString($format)
    }
    catch {
        throw "Failed to format date time object ($dateTimeObject) as string: $($_.Exception.Message)"
    }
}


Function Format-ManagementPackResult {
    <#
    .SYNOPSIS
    Formats a SCOM ManagementPack SDK object into a result hashtable.

    .PARAMETER mp
    The ManagementPack object returned by Get-SCOMManagementPack or Import-SCOMManagementPack.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$mp
    )

    return @{
        id = $mp.Id.ToString()
        name = $mp.Name
        display_name = if ($null -ne $mp.DisplayName) { $mp.DisplayName } else { "" }
        version = if ($null -ne $mp.Version) { $mp.Version.ToString() } else { "" }
        sealed = [bool]$mp.Sealed
        time_created = Format-DateTimeAsStringSafely -dateTimeObject $mp.TimeCreated
        last_modified = Format-DateTimeAsStringSafely -dateTimeObject $mp.LastModified
    }
}


Function Format-NotificationSubscriptionResult {
    <#
    .SYNOPSIS
    Formats a SCOM NotificationSubscription SDK object into a result hashtable.

    .PARAMETER subscription
    The NotificationSubscription object returned by Get-SCOMNotificationSubscription.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$subscription
    )

    $channels = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $subscription.Actions) {
        foreach ($action in $subscription.Actions) {
            if ($null -ne $action.DisplayName) {
                $channels.Add([string]$action.DisplayName)
            }
        }
    }

    $recipient_names = {
        param($recipients)
        $names = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $recipients) {
            foreach ($recipient in $recipients) {
                if ($null -ne $recipient.Name) {
                    $names.Add([string]$recipient.Name)
                }
            }
        }
        return , $names.ToArray()
    }

    $criteria = ""
    if ($null -ne $subscription.Configuration -and $null -ne $subscription.Configuration.Criteria) {
        $criteria = [string]$subscription.Configuration.Criteria
    }

    return @{
        name = [string]$subscription.Name
        display_name = [string]$subscription.DisplayName
        description = if ($null -ne $subscription.Description) { [string]$subscription.Description } else { "" }
        enabled = [bool]$subscription.Enabled
        id = if ($null -ne $subscription.Id) { $subscription.Id.ToString() } else { "" }
        channels = $channels.ToArray()
        subscribers = & $recipient_names $subscription.ToRecipients
        criteria = $criteria
    }
}


Function Format-PendingManagementResult {
    <#
    .SYNOPSIS
    Formats a SCOM AgentPendingAction SDK object into a result hashtable.

    .PARAMETER action
    The AgentPendingAction object returned by Get-SCOMPendingManagement.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$action
    )

    return @{
        agent_name = [string]$action.AgentName
        management_server_name = [string]$action.ManagementServerName
        action_type = [string]$action.AgentPendingActionType
        last_modified = Format-DateTimeAsStringSafely -dateTimeObject $action.LastModified
    }
}


Function Format-NotificationChannelResult {
    <#
    .SYNOPSIS
    Formats a SCOM NotificationChannel SDK object into a result hashtable.

    .PARAMETER channel
    The NotificationChannel object returned by Get-SCOMNotificationChannel.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$channel
    )

    return @{
        display_name = [string]$channel.DisplayName
        channel_type = [string]$channel.ChannelType
        action = [string]$channel.Action
        endpoint = [string]$channel.Endpoint
        management_group = [string]$channel.ManagementGroup
    }
}


Function Format-NotificationSubscriberResult {
    <#
    .SYNOPSIS
    Formats a SCOM NotificationSubscriber SDK object into a result hashtable.

    .PARAMETER subscriber
    The NotificationSubscriber object returned by Get-SCOMNotificationSubscriber.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$subscriber
    )

    $devices = [System.Collections.Generic.List[hashtable]]::new()
    if ($null -ne $subscriber.Devices) {
        foreach ($device in $subscriber.Devices) {
            $devices.Add(@{
                    name = [string]$device.Name
                    protocol = [string]$device.Protocol
                    address = [string]$device.Address
                })
        }
    }

    return @{
        name = [string]$subscriber.Name
        id = if ($null -ne $subscriber.Id) { $subscriber.Id.ToString() } else { "" }
        devices = $devices.ToArray()
    }
}


Function Format-RunAsAccountResult {
    <#
    .SYNOPSIS
    Formats a SCOM RunAsAccount SDK object into a result hashtable.

    .PARAMETER account
    The RunAsAccount object returned by Get-SCOMRunAsAccount.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$account
    )

    return @{
        id = $account.Id.ToString()
        name = $account.Name
        description = if ($null -ne $account.Description) { $account.Description } else { "" }
        domain = if ($null -ne $account.Domain) { $account.Domain } else { "" }
        user_name = if ($null -ne $account.UserName) { $account.UserName } else { "" }
        account_type = if ($null -ne $account.AccountType) { $account.AccountType.ToString() } else { "" }
        last_modified = Format-DateTimeAsStringSafely -dateTimeObject $account.LastModified
    }
}


Function Test-SCOMManagementPackIdentifier {
    <#
    .SYNOPSIS
    Returns $true if a string is a valid SCOM management pack element identifier.

    .DESCRIPTION
    Several SCOM objects (notification channel endpoints, notification subscriptions) are
    stored as management pack elements whose internal ID must satisfy the
    ManagementPackUniqueIdentifier XSD pattern: it must start with a letter or underscore
    and contain only letters, digits, underscores, and dots. Spaces and other punctuation
    are not permitted. Passing a non-conforming value produces a cryptic
    "endpoint could not be inserted" / "not valid for insert" error from the SDK.

    .PARAMETER value
    The candidate identifier string.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()]$value
    )

    if ([string]::IsNullOrEmpty($value)) {
        return $false
    }

    return ([string]$value -match '^[A-Za-z_][A-Za-z0-9_.]*$')
}


Function ConvertTo-SCOMManagementPackIdentifier {
    <#
    .SYNOPSIS
    Converts an arbitrary string into a valid SCOM management pack element identifier.

    .DESCRIPTION
    Produces a deterministic identifier suitable for use as a default internal name when the
    caller only supplied a friendly display name. Removes every character that is not a
    letter, digit, underscore, or dot, then guarantees the result begins with a letter or
    underscore (prefixing "Scom_" when required). See Test-SCOMManagementPackIdentifier for
    the pattern rationale.

    .PARAMETER value
    The source string (typically a display name) to convert.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$value
    )

    $sanitized = ($value -replace '[^A-Za-z0-9_.]', '')

    if ($sanitized -eq '' -or $sanitized -notmatch '^[A-Za-z_]') {
        $sanitized = "Scom_$sanitized"
    }

    return $sanitized
}


Function Format-ModuleParamAsCmdletArgument {
    <#
    .SYNOPSIS
    Builds a cmdlet argument hashtable from Ansible module parameters using mapping tables.

    .DESCRIPTION
    Takes three mapping hashtables (direct, datetime, switch) whose keys are Ansible module
    parameter names and values are the corresponding PowerShell cmdlet parameter names.
    Returns a splatting-ready hashtable containing only parameters that were provided
    (non-null / non-false) by the caller.

    .PARAMETER module
    The Ansible module object providing .Params access.

    .PARAMETER direct_mapped_params
    Hashtable mapping Ansible param name -> cmdlet param name for string/int/list values.

    .PARAMETER datetime_params
    Hashtable mapping Ansible param name -> cmdlet param name for values that must be
    cast to [datetime] before passing to the cmdlet.

    .PARAMETER switch_params
    Hashtable mapping Ansible param name -> cmdlet param name for boolean params that
    map to PowerShell [switch] arguments.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][hashtable]$direct_mapped_params,
        [Parameter(Mandatory = $true)][hashtable]$datetime_params,
        [Parameter(Mandatory = $true)][hashtable]$switch_params
    )

    $cmdlet_arguments = @{}

    foreach ($param in $direct_mapped_params.Keys) {
        $cmdlet_option = $direct_mapped_params.$param
        if ($null -ne $module.Params.$param) {
            $cmdlet_arguments.$cmdlet_option = $module.Params.$param
        }
    }

    foreach ($param in $datetime_params.Keys) {
        $datetime_param = $datetime_params.$param
        if ($null -ne $module.Params.$param) {
            $cmdlet_arguments.$datetime_param = $(Get-Date $module.Params.$param)
        }
    }

    foreach ($param in $switch_params.Keys) {
        $switch_param = $switch_params.$param
        if ($module.Params.$param -eq $true) {
            $cmdlet_arguments.$switch_param = $true
        }
    }

    return $cmdlet_arguments
}
