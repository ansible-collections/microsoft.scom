#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



Function Resolve-SCOMChannelObject {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string[]]$channels
    )

    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($channel_name in $channels) {
        $found = $null
        try {
            $found = @(Get-SCOMNotificationChannel -DisplayName $channel_name -ErrorAction SilentlyContinue)
        }
        catch {
            $module.FailJson("Failed to resolve notification channel '$channel_name': $($_.Exception.Message)", $_)
        }
        if ($null -eq $found -or $found.Count -eq 0) {
            $module.FailJson("Notification channel '$channel_name' was not found. Create it first with the notification_channel module.")
        }
        if ($found.Count -gt 1) {
            $module.FailJson(
                "Notification channel name '$channel_name' is ambiguous — $($found.Count) channels share this display name. " +
                "Rename the channels so each has a unique display name before referencing them in a subscription."
            )
        }
        $resolved.Add($found[0])
    }
    return , $resolved.ToArray()
}


Function Resolve-SCOMSubscriberObject {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string[]]$subscribers
    )

    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($subscriber_name in $subscribers) {
        $found = $null
        try {
            $found = @(Get-SCOMNotificationSubscriber -Name $subscriber_name -ErrorAction SilentlyContinue)
        }
        catch {
            $module.FailJson("Failed to resolve notification subscriber '$subscriber_name': $($_.Exception.Message)", $_)
        }
        if ($null -eq $found -or $found.Count -eq 0) {
            $module.FailJson("Notification subscriber '$subscriber_name' was not found. Create it first with the notification_subscriber module.")
        }
        if ($found.Count -gt 1) {
            $module.FailJson(
                "Notification subscriber name '$subscriber_name' is ambiguous — $($found.Count) subscribers share this name. " +
                "Rename the subscribers so each has a unique name before referencing them in a subscription."
            )
        }
        $resolved.Add($found[0])
    }
    return , $resolved.ToArray()
}


Function Build-SCOMCriteriaXml {
    <#
    .SYNOPSIS
    Builds a SCOM alert criteria XML string from structured filter input.
    #>
    param(
        [Parameter(Mandatory = $true)][object[]]$filters,
        [Parameter(Mandatory = $false)][string]$group_operator = $null
    )

    $value_map = @{
        "critical" = 2
        "warning" = 1
        "information" = 0
        "high" = 2
        "medium" = 1
        "low" = 0
    }
    $operator_map = @{
        "equal" = "Equal"
        "not_equal" = "NotEqual"
        "greater" = "Greater"
        "greater_equal" = "GreaterEqual"
        "less" = "Less"
        "less_equal" = "LessEqual"
    }
    $severity_values = @("critical", "warning", "information")
    $priority_values = @("low", "medium", "high")

    $simple_expressions = [System.Collections.Generic.List[string]]::new()
    foreach ($filter in $filters) {
        $prop = $filter.property
        $val_name = $filter.value

        if ($prop -eq "severity" -and $val_name -notin $severity_values) {
            throw "Value '$val_name' is not valid for property 'severity'. Valid values: $($severity_values -join ', ')."
        }
        if ($prop -eq "priority" -and $val_name -notin $priority_values) {
            throw "Value '$val_name' is not valid for property 'priority'. Valid values: $($priority_values -join ', ')."
        }

        $prop_xml = if ($prop -eq "severity") { "Severity" } else { "Priority" }
        $op_xml = $operator_map[$filter.operator]
        $val_xml = $value_map[$val_name]

        $simple_expressions.Add(
            "<SimpleExpression>" +
            "<ValueExpression><Property>$prop_xml</Property></ValueExpression>" +
            "<Operator>$op_xml</Operator>" +
            "<ValueExpression><Value>$val_xml</Value></ValueExpression>" +
            "</SimpleExpression>"
        )
    }

    if ($simple_expressions.Count -eq 1) {
        return $simple_expressions[0]
    }

    if ([string]::IsNullOrEmpty($group_operator)) {
        throw "group_operator is required when multiple filters are specified. Use 'and' or 'or'."
    }

    $logical_tag = if ($group_operator -eq "and") { "And" } else { "Or" }
    $xml = "<$logical_tag>"
    foreach ($expr in $simple_expressions) {
        $xml += "<Expression>$expr</Expression>"
    }
    $xml += "</$logical_tag>"
    return $xml
}


$spec = @{
    options = @{
        name = @{ type = "str"; required = $true }
        display_name = @{ type = "str"; required = $false; default = $null }
        description = @{ type = "str"; required = $false; default = $null }
        channels = @{ type = "list"; elements = "str"; required = $false; default = $null }
        subscribers = @{ type = "list"; elements = "str"; required = $false; default = $null }
        criteria = @{
            type = "dict"
            required = $false
            default = $null
            options = @{
                group_operator = @{
                    type = "str"
                    required = $false
                    default = $null
                    choices = @("and", "or")
                }
                filters = @{
                    type = "list"
                    elements = "dict"
                    required = $true
                    options = @{
                        property = @{
                            type = "str"
                            required = $true
                            choices = @("severity", "priority")
                        }
                        operator = @{
                            type = "str"
                            required = $true
                            choices = @("equal", "not_equal", "greater", "greater_equal", "less", "less_equal")
                        }
                        value = @{
                            type = "str"
                            required = $true
                            choices = @("critical", "warning", "information", "low", "medium", "high")
                        }
                    }
                }
            }
        }
        enabled = @{ type = "bool"; required = $false; default = $null }
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
    }
    required_if = @(
        , @("state", "present", @("enabled"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$display_name = if ($null -ne $module.Params.display_name) { $module.Params.display_name } else { $name }
$description = $module.Params.description
$channels = $module.Params.channels
$subscribers = $module.Params.subscribers
$criteria = $module.Params.criteria
$enabled = $module.Params.enabled
$state = $module.Params.state

if (-not (Test-SCOMManagementPackIdentifier -value $name)) {
    $module.FailJson(
        "The 'name' parameter '$name' is not a valid SCOM internal name. " +
        "It must start with a letter or underscore and contain only letters, digits, " +
        "underscores, and dots (no spaces). Use 'display_name' for a friendly label."
    )
}

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$existing = $null
try {
    $existing = Get-SCOMNotificationSubscription -Name $name -ErrorAction SilentlyContinue
}
catch {
    $module.FailJson("Failed to query SCOM notification subscription '$name': $($_.Exception.Message)", $_)
}

if ($state -eq "absent") {
    if ($null -eq $existing) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $existing | Remove-SCOMNotificationSubscription -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM notification subscription '$name': $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}

# state == present
if ($null -ne $existing) {
    $current = Format-NotificationSubscriptionResult -subscription $existing

    if ($channels.Count -gt 0) {
        $channels_differ = $null -ne (Compare-Object ($current.channels | Sort-Object) ($channels | Sort-Object))
        if ($channels_differ) {
            $module.Warn(
                "Notification subscription '$name' already exists with different channels. " +
                "Channel membership cannot be updated in-place. " +
                "Remove the subscription with state=absent and recreate it to change channels."
            )
        }
    }

    if ($null -ne $criteria) {
        $module.Warn(
            "Notification subscription '$name' already exists. " +
            "Criteria cannot be applied to an existing subscription. " +
            "Remove it with state=absent and recreate it to set criteria."
        )
    }

    $subscribers_differ = ($subscribers.Count -gt 0) -and
        ($null -ne (Compare-Object @($current.subscribers | Sort-Object) @($subscribers | Sort-Object)))
    $needs_subscriber_update = $subscribers_differ

    $enabled_differs = [bool]$existing.Enabled -ne $enabled

    if ($needs_subscriber_update -or $enabled_differs) {
        # Validate subscriber names before committing changed=true.
        if ($needs_subscriber_update) {
            $sub_objects = Resolve-SCOMSubscriberObject -module $module -subscribers $subscribers
        }

        $module.Result.changed = $true
        if (-not $module.CheckMode) {
            if ($needs_subscriber_update) {
                try {
                    $existing.ToRecipients.Clear()
                    foreach ($s in $sub_objects) { $existing.ToRecipients.Add($s) }
                    $existing.Update()
                }
                catch {
                    $module.FailJson("Failed to update subscribers for notification subscription '$name': $($_.Exception.Message)", $_)
                }
            }
            if ($enabled_differs) {
                try {
                    if ($enabled) {
                        $existing | Enable-SCOMNotificationSubscription -ErrorAction Stop
                    }
                    else {
                        $existing | Disable-SCOMNotificationSubscription -ErrorAction Stop
                    }
                }
                catch {
                    $action = if ($enabled) { "enable" } else { "disable" }
                    $module.FailJson("Failed to $action SCOM notification subscription '$name': $($_.Exception.Message)", $_)
                }
            }
            try {
                $existing = Get-SCOMNotificationSubscription -Name $name -ErrorAction Stop
            }
            catch {
                $module.Warn("Subscription was updated but could not be re-fetched for result: $($_.Exception.Message)")
            }
        }
    }
    else {
        $module.Result.changed = $false
    }
    $module.Result.subscription = Format-NotificationSubscriptionResult -subscription $existing
    $module.ExitJson()
}
else {
    # Subscription does not exist — validate create requirements before proceeding.
    if ($null -eq $channels -or $channels.Count -eq 0) {
        $module.FailJson("'channels' requires at least one entry when creating a new notification subscription.")
    }
    if ($null -eq $subscribers -or $subscribers.Count -eq 0) {
        $module.FailJson("'subscribers' requires at least one entry when creating a new notification subscription.")
    }

    # Resolve channels and subscribers and validate criteria before committing changed=true
    # so that check mode accurately reflects whether the real run would succeed.
    $channel_objects = Resolve-SCOMChannelObject -module $module -channels $channels
    $subscriber_objects = Resolve-SCOMSubscriberObject -module $module -subscribers $subscribers

    $criteria_xml = $null
    if ($null -ne $criteria) {
        try {
            $criteria_xml = Build-SCOMCriteriaXml -filters $criteria.filters -group_operator $criteria.group_operator
        }
        catch {
            $module.FailJson("Invalid criteria: $($_.Exception.Message)")
        }
    }

    $module.Result.changed = $true

    if (-not $module.CheckMode) {
        $add_arguments = @{
            Name = $name
            DisplayName = $display_name
            Subscriber = $subscriber_objects
            Channel = $channel_objects
        }
        if ($null -ne $description) { $add_arguments.Description = $description }
        if ($null -ne $criteria_xml) { $add_arguments.Criteria = $criteria_xml }
        if (-not $enabled) { $add_arguments.Disabled = $true }

        try {
            $null = Add-SCOMNotificationSubscription @add_arguments -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to create SCOM notification subscription '$name': $($_.Exception.Message)", $_)
        }

        try {
            $existing = Get-SCOMNotificationSubscription -Name $name -ErrorAction Stop
        }
        catch {
            $module.Warn("Notification subscription was created but could not be re-fetched for result: $($_.Exception.Message)")
        }
    }

    if ($null -ne $existing) {
        $module.Result.subscription = Format-NotificationSubscriptionResult -subscription $existing
    }

    $module.ExitJson()
}
