#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



$spec = @{
    options = @{
        name = @{ type = "str"; required = $true }
        devices = @{
            type = "list"
            elements = "dict"
            required = $false
            default = @()
            options = @{
                address = @{ type = "str"; required = $true }
                name = @{ type = "str"; required = $false; default = $null }
                type = @{
                    type = "str"
                    required = $false
                    default = "smtp"
                    choices = @("smtp", "sms", "sip")
                }
            }
        }
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
    }
    required_if = @(
        , @("state", "present", @("devices"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$devices = $module.Params.devices
$state = $module.Params.state

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$existing = $null
try {
    $existing = Get-SCOMNotificationSubscriber -Name $name -ErrorAction SilentlyContinue
}
catch {
    $module.FailJson("Failed to query SCOM notification subscriber '$name': $($_.Exception.Message)", $_)
}

if ($state -eq "absent") {
    if ($null -eq $existing) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $existing | Remove-SCOMNotificationSubscriber -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM notification subscriber '$name': $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}

# state == present
if ($null -ne $existing) {
    $module.Result.changed = $false
    $module.Result.subscriber = Format-NotificationSubscriberResult -subscriber $existing
    $module.ExitJson()
}

if ($devices.Count -eq 0) {
    $module.FailJson("At least one entry in 'devices' is required to create notification subscriber '$name'.")
}

foreach ($device in $devices) {
    if ($device.type -eq "smtp" -and $device.address -notmatch '@') {
        $module.FailJson(
            "Add a valid type: 'smtp', 'sms', or 'sip' to the device. " +
            "Device address '$($device.address)' is not a valid email address for default type smtp."
        )
    }
}

$module.Result.changed = $true

if (-not $module.CheckMode) {
    $device_table = @{}
    foreach ($device in $devices) {
        $device_address = switch ($device.type) {
            "sms" { "sms:$($device.address)" }
            "sip" { "sip:$($device.address)" }
            default { $device.address }
        }
        $device_name = if ($null -ne $device.name) { $device.name } else { $device_address }
        $device_table[$device_name] = $device_address
    }

    try {
        $null = Add-SCOMNotificationSubscriber -Name $name -DeviceTable $device_table -ErrorAction Stop
    }
    catch {
        $module.FailJson("Failed to create SCOM notification subscriber '$name': $($_.Exception.Message)", $_)
    }

    try {
        $existing = Get-SCOMNotificationSubscriber -Name $name -ErrorAction Stop
    }
    catch {
        $module.Warn("Notification subscriber was created but could not be re-fetched for result: $($_.Exception.Message)")
    }
}

if ($null -ne $existing) {
    $module.Result.subscriber = Format-NotificationSubscriberResult -subscriber $existing
}

$module.ExitJson()
