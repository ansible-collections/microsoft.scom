#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


# Maps the MaintenanceModeReason enum name -> the Ansible reason choice.
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


$spec = @{
    options = @{
        name = @{ type = "str"; required = $false; default = $null }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$summaries = $null
try {
    $summaries = @(Get-SCOMMaintenanceScheduleList -ErrorAction Stop)
}
catch {
    $module.FailJson("Failed to list SCOM maintenance schedules: $($_.Exception.Message)", $_)
}

if ($null -ne $name) {
    $summaries = @($summaries | Where-Object { $_.ScheduleName -eq $name })
}

$result_schedules = [System.Collections.Generic.List[hashtable]]::new()
foreach ($summary in $summaries) {
    $full = $null
    try {
        $full = Get-SCOMMaintenanceSchedule -ID $summary.ScheduleId -ErrorAction Stop
    }
    catch {
        $module.Warn("Failed to retrieve maintenance schedule '$($summary.ScheduleName)': $($_.Exception.Message)")
        continue
    }
    $result_schedules.Add((Format-MaintenanceScheduleResult -schedule $full))
}

$module.Result.changed = $false
$module.Result.schedules = $result_schedules.ToArray()

$module.ExitJson()
