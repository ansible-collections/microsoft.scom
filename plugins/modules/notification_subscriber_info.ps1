#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



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

$subscribers = $null
try {
    if ($null -ne $name) {
        $subscribers = Get-SCOMNotificationSubscriber -Name $name -ErrorAction SilentlyContinue
    }
    else {
        $subscribers = Get-SCOMNotificationSubscriber -ErrorAction Stop
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM notification subscribers: $($_.Exception.Message)", $_)
}

$result_subscribers = [System.Collections.Generic.List[hashtable]]::new()
foreach ($subscriber in @($subscribers)) {
    if ($null -ne $subscriber) {
        $result_subscribers.Add((Format-NotificationSubscriberResult -subscriber $subscriber))
    }
}

$module.Result.changed = $false
$module.Result.subscribers = $result_subscribers.ToArray()

$module.ExitJson()
