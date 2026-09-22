# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# Shared utilities for the maintenance_schedule and maintenance_schedule_info modules.

# Single source of truth for the Ansible frequency choice -> SCOM FreqType int mapping.
# Defined as a function so it is callable from any scope without relying on module-level
# variable export, which is not supported when psm1 files are dot-sourced by Ansible.
Function Get-FrequencyMap {
    return @{
        once = 1
        daily = 4
        weekly = 8
        monthly = 16
    }
}


Function ConvertTo-FrequencyInt {
    <#
    .SYNOPSIS
    Converts an Ansible frequency choice string to the SCOM schedule FreqType integer.

    .PARAMETER frequency
    The Ansible frequency choice: once, daily, weekly, or monthly.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$frequency
    )
    return (Get-FrequencyMap)[$frequency]
}


Function ConvertTo-FrequencyString {
    <#
    .SYNOPSIS
    Converts a SCOM schedule FreqType integer to the Ansible frequency choice string.

    .DESCRIPTION
    Performs a reverse lookup of the frequency map. Returns "custom_<n>" for any
    FreqType not in the map (e.g. SCOM custom schedules).

    .PARAMETER freqType
    The FreqType integer from a SCOM ScheduleRecurrence object.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$freqType
    )
    $map = Get-FrequencyMap
    $int_val = [int]$freqType
    $match = $map.Keys | Where-Object { $map[$_] -eq $int_val } | Select-Object -First 1
    if ($match) {
        return $match
    }
    return "custom_$int_val"
}


Function ConvertTo-ReasonString {
    <#
    .SYNOPSIS
    Converts a SCOM MaintenanceModeReason string to the Ansible snake_case choice.

    .DESCRIPTION
    Uses a regex to insert underscores before each uppercase letter and lowercases the result.
    Example: "PlannedOther" -> "planned_other".

    .PARAMETER reason
    The MaintenanceModeReason value (or its string representation) returned by SCOM.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$reason
    )
    return ($([string]$reason) -creplace '([A-Z])', '_$1').TrimStart('_').ToLower()
}


Function ConvertTo-PascalCase {
    <#
    .SYNOPSIS
    Converts a snake_case string to PascalCase.

    .DESCRIPTION
    Splits the value on underscores and capitalises the first letter of each word.
    Example: "planned_other" -> "PlannedOther".
    Used to convert Ansible reason choices back to the SCOM SDK enum member name.

    .PARAMETER value
    The snake_case string to convert.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$value
    )
    return ($value -split '_' | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
}


Function Get-MonitoringObjectIdString {
    <#
    .SYNOPSIS
    Returns the sorted list of monitoring object GUID strings attached to a schedule.

    .PARAMETER schedule
    The SCOM MaintenanceSchedule object whose MonitoringObjects property is inspected.
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


Function Format-MaintenanceScheduleResult {
    <#
    .SYNOPSIS
    Converts a SCOM MaintenanceSchedule object into the standard Ansible result hashtable.

    .PARAMETER schedule
    The SCOM MaintenanceSchedule object to format.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$schedule
    )

    $frequency = ""
    if ($null -ne $schedule.ScheduleRecurrence) {
        $frequency = ConvertTo-FrequencyString -freqType $schedule.ScheduleRecurrence.FreqType
    }

    $comments = ""
    if ($null -ne $schedule.Comments) {
        $comments = [string]$schedule.Comments
    }

    return @{
        schedule_id = $schedule.ScheduleId.ToString()
        name = [string]$schedule.ScheduleName
        enabled = [bool]$schedule.IsEnabled
        recursive = [bool]$schedule.Recursive
        duration = [int]$schedule.Duration
        reason = ConvertTo-ReasonString -reason $schedule.ReasonCode
        comments = $comments
        active_start_time = Format-DateTimeAsStringSafely -dateTimeObject $schedule.ActiveStartTime
        active_end_date = Format-DateTimeAsStringSafely -dateTimeObject $schedule.ActiveEndDate
        is_recurrence = [bool]$schedule.IsRecurrence
        frequency = $frequency
        monitoring_objects = @(Get-MonitoringObjectIdString -schedule $schedule)
    }
}
