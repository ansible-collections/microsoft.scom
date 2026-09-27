#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._RunAsDistributionUtils


$spec = @{
    options = @{
        run_as_account = @{ type = "str"; required = $false; default = $null }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$run_as_account = $module.Params.run_as_account

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$accounts = $null
try {
    if ($null -ne $run_as_account) {
        $accounts = Get-SCOMRunAsAccount -Name $run_as_account -ErrorAction Stop
    }
    else {
        $accounts = Get-SCOMRunAsAccount -ErrorAction Stop
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM RunAs accounts: $($_.Exception.Message)", $_)
}

$result_distributions = [System.Collections.Generic.List[hashtable]]::new()
if ($null -ne $accounts) {
    foreach ($account in $accounts) {
        $distribution = $null
        try {
            $distribution = Get-SCOMRunAsDistribution -RunAsAccount $account -ErrorAction Stop
        }
        catch {
            $module.Warn("Failed to retrieve distribution for RunAs account '$($account.Name)': $($_.Exception.Message)")
            continue
        }

        $result_distributions.Add(@{
                run_as_account = $account.Name
                security_level = (Get-SecurityLevelMap).SCOMToAnsible[[string]$distribution.Security]
                computers = @(Get-DistributionComputerName -distribution $distribution)
            })
    }
}

$module.Result.changed = $false
$module.Result.distributions = $result_distributions.ToArray()

$module.ExitJson()
