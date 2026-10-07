#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



$spec = @{
    options = @{
        name = @{ type = "str"; required = $false; default = $null }
        display_name = @{ type = "str"; required = $false; default = $null }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$display_name = $module.Params.display_name

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$subscriptions = $null
try {
    if ($null -ne $name) {
        $subscriptions = Get-SCOMNotificationSubscription -Name $name -ErrorAction SilentlyContinue
    }
    elseif ($null -ne $display_name) {
        $subscriptions = Get-SCOMNotificationSubscription -DisplayName $display_name -ErrorAction SilentlyContinue
    }
    else {
        $subscriptions = Get-SCOMNotificationSubscription -ErrorAction Stop
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM notification subscriptions: $($_.Exception.Message)", $_)
}

$result_subscriptions = [System.Collections.Generic.List[hashtable]]::new()
foreach ($subscription in @($subscriptions)) {
    if ($null -ne $subscription) {
        $result_subscriptions.Add((Format-NotificationSubscriptionResult -subscription $subscription))
    }
}

$module.Result.changed = $false
$module.Result.subscriptions = $result_subscriptions.ToArray()

$module.ExitJson()
