#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



$spec = @{
    options = @{
        name = @{ type = "str"; required = $false; default = $null }
        id = @{ type = "str"; required = $false; default = $null }
    }
    mutually_exclusive = @(
        , @("name", "id")
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$id = $module.Params.id

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$accounts = $null
if ($null -ne $id) {
    try {
        $accounts = Get-SCOMRunAsAccount -Id $id -ErrorAction Stop
    }
    catch {
        $accounts = $null
    }
}
else {
    try {
        if ($null -ne $name) {
            $accounts = Get-SCOMRunAsAccount -Name $name -ErrorAction Stop
        }
        else {
            $accounts = Get-SCOMRunAsAccount -ErrorAction Stop
        }
    }
    catch {
        $module.FailJson("Failed to retrieve SCOM RunAs accounts: $($_.Exception.Message)", $_)
    }
}

$result_accounts = [System.Collections.Generic.List[hashtable]]::new()
if ($null -ne $accounts) {
    foreach ($account in $accounts) {
        $result_accounts.Add((Format-RunAsAccountResult -account $account))
    }
}

$module.Result.changed = $false
$module.Result.run_as_accounts = $result_accounts.ToArray()

$module.ExitJson()
