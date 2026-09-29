#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



$spec = @{
    options = @{
        display_name = @{ type = "str"; required = $false; default = $null }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$display_name = $module.Params.display_name

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$channels = $null
try {
    if ($null -ne $display_name) {
        $channels = Get-SCOMNotificationChannel -DisplayName $display_name -ErrorAction SilentlyContinue
    }
    else {
        $channels = Get-SCOMNotificationChannel -ErrorAction Stop
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM notification channels: $($_.Exception.Message)", $_)
}

$result_channels = [System.Collections.Generic.List[hashtable]]::new()
foreach ($channel in @($channels)) {
    if ($null -ne $channel) {
        $result_channels.Add((Format-NotificationChannelResult -channel $channel))
    }
}

$module.Result.changed = $false
$module.Result.channels = $result_channels.ToArray()

$module.ExitJson()
