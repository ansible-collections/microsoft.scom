#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._MaintenanceScheduleUtils



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
