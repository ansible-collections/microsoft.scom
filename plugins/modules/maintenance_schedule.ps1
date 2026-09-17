#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


# Maps the Ansible frequency choice -> the SCOM schedule FreqType integer (SQL-Agent style).
$FREQUENCY_MAP = @{
    once = 1
    daily = 4
    weekly = 8
    monthly = 16
}

# Maps the Ansible reason choice -> the MaintenanceModeReason enum name.
$REASON_MAP = @{
    planned_other = "PlannedOther"
    unplanned_other = "UnplannedOther"
    planned_hardware_maintenance = "PlannedHardwareMaintenance"
    unplanned_hardware_maintenance = "UnplannedHardwareMaintenance"
    planned_hardware_installation = "PlannedHardwareInstallation"
    unplanned_hardware_installation = "UnplannedHardwareInstallation"
    planned_operating_system_reconfiguration = "PlannedOperatingSystemReconfiguration"
    unplanned_operating_system_reconfiguration = "UnplannedOperatingSystemReconfiguration"
    planned_application_maintenance = "PlannedApplicationMaintenance"
    unplanned_application_maintenance = "UnplannedApplicationMaintenance"
    application_installation = "ApplicationInstallation"
    application_unresponsive = "ApplicationUnresponsive"
    application_unstable = "ApplicationUnstable"
    security_issue = "SecurityIssue"
    loss_of_network_connectivity = "LossOfNetworkConnectivity"
}


Function ConvertTo-FrequencyString {
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$freqType
    )

    switch ([int]$freqType) {
        1 { return "once" }
        4 { return "daily" }
        8 { return "weekly" }
        16 { return "monthly" }
        default { return "custom_$freqType" }
    }
}


Function ConvertTo-ReasonString {
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$reason
    )

    $reason_name = [string]$reason
    foreach ($key in $REASON_MAP.Keys) {
        if ($REASON_MAP[$key] -eq $reason_name) {
            return $key
        }
    }
    return $reason_name
}


Function Get-MonitoringObjectIdString {
    <#
    Returns the sorted list of monitoring object GUID strings currently attached to a
    maintenance schedule (the MonitoringObjects property is a list of GUIDs).
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$schedule
    )

    if ($null -eq $schedule -or $null -eq $schedule.MonitoringObjects) {
        return @()
    }

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($object_id in $schedule.MonitoringObjects) {
        $ids.Add([string]$object_id)
    }

    return @($ids | Sort-Object -Unique)
}


Function Resolve-SCOMMonitoringObjectId {
    <#
    Resolves a group or object display name to its SCOM monitoring object GUID(s).
    Groups are preferred (the common maintenance target); if no group matches, a class
    instance lookup is attempted. Fails via the module when nothing resolves.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$target
    )

    $group = $null
    try {
        $group = Get-SCOMGroup -DisplayName $target -ErrorAction SilentlyContinue
    }
    catch {
        $module.FailJson("Failed to resolve group '$target': $($_.Exception.Message)", $_)
    }
    if ($null -ne $group) {
        return @(@($group) | ForEach-Object { $_.Id.ToString() })
    }

    $instance = $null
    try {
        $instance = Get-SCOMClassInstance -Name $target -ErrorAction SilentlyContinue
    }
    catch {
        $module.FailJson("Failed to resolve monitoring object '$target': $($_.Exception.Message)", $_)
    }
    if ($null -ne $instance) {
        return @(@($instance) | ForEach-Object { $_.Id.ToString() })
    }

    $module.FailJson("Could not resolve monitoring object '$target' to a SCOM group or class instance.")
}


Function Format-MaintenanceScheduleResult {
    param (
        [Parameter(Mandatory = $true)][object]$schedule
    )

    $frequency = if ($null -ne $schedule.ScheduleRecurrence) {
        ConvertTo-FrequencyString -freqType $schedule.ScheduleRecurrence.FreqType
    }
    else {
        ""
    }

    return @{
        schedule_id = $schedule.ScheduleId.ToString()
        name = [string]$schedule.ScheduleName
        enabled = [bool]$schedule.IsEnabled
        recursive = [bool]$schedule.Recursive
        duration = [int]$schedule.Duration
        reason = ConvertTo-ReasonString -reason $schedule.ReasonCode
        comments = if ($null -ne $schedule.Comments) { [string]$schedule.Comments } else { "" }
        active_start_time = Format-DateTimeAsStringSafely -dateTimeObject $schedule.ActiveStartTime
        active_end_date = Format-DateTimeAsStringSafely -dateTimeObject $schedule.ActiveEndDate
        is_recurrence = [bool]$schedule.IsRecurrence
        frequency = $frequency
        monitoring_objects = @(Get-MonitoringObjectIdString -schedule $schedule)
    }
}


Function Get-MaintenanceScheduleByName {
    <#
    Returns the full maintenance schedule object whose ScheduleName matches, or $null.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$name
    )

    $summary = $null
    try {
        $summary = @(Get-SCOMMaintenanceScheduleList -ErrorAction Stop | Where-Object { $_.ScheduleName -eq $name })
    }
    catch {
        $module.FailJson("Failed to list SCOM maintenance schedules: $($_.Exception.Message)", $_)
    }

    if ($summary.Count -eq 0) {
        return $null
    }
    if ($summary.Count -gt 1) {
        $module.FailJson("Multiple SCOM maintenance schedules found with name '$name'. The name must be unique.")
    }

    try {
        return Get-SCOMMaintenanceSchedule -ID $summary[0].ScheduleId -ErrorAction Stop
    }
    catch {
        $module.FailJson("Failed to retrieve SCOM maintenance schedule '$name': $($_.Exception.Message)", $_)
    }
}


$spec = @{
    options = @{
        name = @{ type = "str"; required = $true }
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
        monitoring_objects = @{ type = "list"; elements = "str"; required = $false; default = $null }
        duration = @{ type = "int"; required = $false; default = $null }
        reason = @{
            type = "str"
            required = $false
            default = $null
            choices = @(
                "planned_other", "unplanned_other",
                "planned_hardware_maintenance", "unplanned_hardware_maintenance",
                "planned_hardware_installation", "unplanned_hardware_installation",
                "planned_operating_system_reconfiguration", "unplanned_operating_system_reconfiguration",
                "planned_application_maintenance", "unplanned_application_maintenance",
                "application_installation", "application_unresponsive", "application_unstable",
                "security_issue", "loss_of_network_connectivity"
            )
        }
        active_start_time = @{ type = "str"; required = $false; default = $null }
        active_end_date = @{ type = "str"; required = $false; default = $null }
        comments = @{ type = "str"; required = $false; default = $null }
        enabled = @{ type = "bool"; required = $false; default = $true }
        recursive = @{ type = "bool"; required = $false; default = $true }
        frequency = @{
            type = "str"
            required = $false
            default = "once"
            choices = @("once", "daily", "weekly", "monthly")
        }
        freq_interval = @{ type = "int"; required = $false; default = $null }
        freq_recurrence_factor = @{ type = "int"; required = $false; default = $null }
    }
    required_if = @(
        , @("state", "present", @("duration", "reason", "active_start_time"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$state = $module.Params.state

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$existing = Get-MaintenanceScheduleByName -module $module -name $name

if ($state -eq "absent") {
    if ($null -eq $existing) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Remove-SCOMMaintenanceSchedule -IDs $existing.ScheduleId -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM maintenance schedule '$name': $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}

# state == present - build the desired configuration.
$duration = $module.Params.duration
$reason_enum = $REASON_MAP[$module.Params.reason]
$comments = $module.Params.comments
$enabled = $module.Params.enabled
$recursive = $module.Params.recursive
$freq_type = $FREQUENCY_MAP[$module.Params.frequency]
# FreqInterval is not applicable for one-time schedules (SCOM stores 0).
# For recurring schedules default to 1 when the user does not supply a value.
$freq_interval = if ($null -ne $module.Params.freq_interval) {
    $module.Params.freq_interval
}
elseif ($module.Params.frequency -eq "once") {
    0
}
else {
    1
}

$active_start_time = $null
try {
    $active_start_time = [datetime]$module.Params.active_start_time
}
catch {
    $module.FailJson("Invalid active_start_time '$($module.Params.active_start_time)': $($_.Exception.Message)", $_)
}

$active_end_date = $null
if ($null -ne $module.Params.active_end_date) {
    try {
        $active_end_date = [datetime]$module.Params.active_end_date
    }
    catch {
        $module.FailJson("Invalid active_end_date '$($module.Params.active_end_date)': $($_.Exception.Message)", $_)
    }
}

# Resolve the desired monitoring objects to a sorted, unique GUID set.
# When omitted (null), existing monitoring objects are left untouched (idempotent).
# An empty list is rejected — a schedule with no targets is invalid in SCOM.
$monitoring_objects_specified = $null -ne $module.Params.monitoring_objects
$desired_object_ids = @()
$desired_object_guids = @()
if ($monitoring_objects_specified) {
    if ($module.Params.monitoring_objects.Count -eq 0) {
        $module.FailJson("'monitoring_objects' must contain at least one entry. A maintenance schedule requires at least one monitoring target.")
    }
    $id_list = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $module.Params.monitoring_objects) {
        foreach ($resolved_id in (Resolve-SCOMMonitoringObjectId -module $module -target $target)) {
            if (-not $id_list.Contains($resolved_id)) {
                $id_list.Add($resolved_id)
            }
        }
    }
    $desired_object_ids = @($id_list | Sort-Object -Unique)
    $desired_object_guids = @($desired_object_ids | ForEach-Object { [guid]$_ })
}

if ($null -eq $existing) {
    # Create a new schedule — monitoring_objects is required here since SCOM needs at least one target.
    if (-not $monitoring_objects_specified) {
        $module.FailJson("'monitoring_objects' is required when creating a new maintenance schedule.")
    }
    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        $new_arguments = @{
            Name = $name
            ActiveStartTime = $active_start_time
            Duration = $duration
            ReasonCode = [Microsoft.EnterpriseManagement.Monitoring.MaintenanceModeReason]$reason_enum
            FreqType = $freq_type
            FreqInterval = $freq_interval
        }
        if ($enabled) { $new_arguments.Enabled = $true }
        if ($recursive) { $new_arguments.Recursive = $true }
        if ($monitoring_objects_specified) { $new_arguments.MonitoringObjects = $desired_object_guids }
        if ($null -ne $active_end_date) { $new_arguments.ActiveEndDate = $active_end_date }
        if ($null -ne $comments) { $new_arguments.Comments = $comments }
        if ($null -ne $module.Params.freq_recurrence_factor) {
            $new_arguments.FreqRecurrenceFactor = $module.Params.freq_recurrence_factor
        }

        try {
            New-SCOMMaintenanceSchedule @new_arguments -ErrorAction Stop | Out-Null
        }
        catch {
            $module.FailJson("Failed to create SCOM maintenance schedule '$name': $($_.Exception.Message)", $_)
        }

        $existing = Get-MaintenanceScheduleByName -module $module -name $name
    }

    if ($null -ne $existing) {
        $module.Result.schedule = Format-MaintenanceScheduleResult -schedule $existing
    }
    $module.ExitJson()
}

# Schedule exists - determine whether an update is required.
$current_object_ids = @(Get-MonitoringObjectIdString -schedule $existing)
$current_freq_type = if ($null -ne $existing.ScheduleRecurrence) { [int]$existing.ScheduleRecurrence.FreqType } else { 0 }
$current_freq_interval = if ($null -ne $existing.ScheduleRecurrence) { [int]$existing.ScheduleRecurrence.FreqInterval } else { 0 }

$compare_format = "yyyy-MM-dd HH:mm:ss"
$current_start = $existing.ActiveStartTime.ToString($compare_format)
$desired_start = $active_start_time.ToString($compare_format)

$needs_update = $false
if ([int]$existing.Duration -ne [int]$duration) { $needs_update = $true }
elseif ([string]$existing.ReasonCode -ne $reason_enum) { $needs_update = $true }
elseif ([bool]$existing.IsEnabled -ne [bool]$enabled) { $needs_update = $true }
elseif ([bool]$existing.Recursive -ne [bool]$recursive) { $needs_update = $true }
elseif ($current_freq_type -ne $freq_type) { $needs_update = $true }
elseif ($current_freq_interval -ne $freq_interval) { $needs_update = $true }
elseif ($current_start -ne $desired_start) { $needs_update = $true }
elseif ($null -ne $comments -and [string]$existing.Comments -ne [string]$comments) { $needs_update = $true }
elseif ($null -ne $active_end_date) {
    $current_end = $existing.ActiveEndDate.ToString($compare_format)
    $desired_end = $active_end_date.ToString($compare_format)
    if ($current_end -ne $desired_end) { $needs_update = $true }
}

if (-not $needs_update -and $monitoring_objects_specified) {
    $diff = Compare-Object -ReferenceObject $current_object_ids -DifferenceObject $desired_object_ids
    if ($null -ne $diff) { $needs_update = $true }
}

if (-not $needs_update) {
    $module.Result.changed = $false
    $module.Result.schedule = Format-MaintenanceScheduleResult -schedule $existing
    $module.ExitJson()
}

$module.Result.changed = $true
if (-not $module.CheckMode) {
    $edit_arguments = @{
        ScheduleId = $existing.ScheduleId
        Name = $name
        Recursive = $recursive
        Enabled = $enabled
        ActiveStartTime = $active_start_time
        Duration = $duration
        ReasonCode = [Microsoft.EnterpriseManagement.Monitoring.MaintenanceModeReason]$reason_enum
        FreqType = $freq_type
        FreqInterval = $freq_interval
    }
    if ($monitoring_objects_specified) { $edit_arguments.MonitoringObjects = $desired_object_guids }
    if ($null -ne $active_end_date) { $edit_arguments.ActiveEndDate = $active_end_date }
    if ($null -ne $comments) { $edit_arguments.Comments = $comments }
    if ($null -ne $module.Params.freq_recurrence_factor) {
        $edit_arguments.FreqRecurrenceFactor = $module.Params.freq_recurrence_factor
    }

    try {
        Edit-SCOMMaintenanceSchedule @edit_arguments -ErrorAction Stop | Out-Null
    }
    catch {
        $module.FailJson("Failed to update SCOM maintenance schedule '$name': $($_.Exception.Message)", $_)
    }

    $existing = Get-MaintenanceScheduleByName -module $module -name $name
}

if ($null -ne $existing) {
    $module.Result.schedule = Format-MaintenanceScheduleResult -schedule $existing
}
$module.ExitJson()
