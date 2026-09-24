#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._RunAsDistributionUtils



Function Resolve-SCOMDistributionTarget {
    <#
    Resolves a target name to its SCOM monitoring object(s) so it can be passed to
    Set-SCOMRunAsDistribution -SecureDistribution. Valid targets are:
      - Health Service objects
      - Resource Pool objects
    Tries HealthService first; falls back to ResourcePool. Fails via the module when
    neither lookup returns a result.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$target
    )

    $health_service_class = $null
    try {
        $health_service_class = Get-SCOMClass -Name "Microsoft.SystemCenter.HealthService" -ErrorAction Stop
    }
    catch {
        $module.FailJson("Failed to load the SCOM HealthService class: $($_.Exception.Message)", $_)
    }

    $health_services = @()
    try {
        $all_hs = Get-SCOMClassInstance -Class $health_service_class -ErrorAction Stop
        $hs_filter = { $_.DisplayName -eq $target -or $_.Name -eq $target -or ($null -ne $_.DisplayName -and ($_.DisplayName.Split(".")[0] -eq $target)) }
        $health_services = @($all_hs | Where-Object $hs_filter)
    }
    catch {
        $module.FailJson("Failed to query SCOM Health Service objects for '$target': $($_.Exception.Message)", $_)
    }

    if ($health_services.Count -gt 0) {
        return $health_services
    }

    $pools = @()
    try {
        $pools = @(Get-SCOMResourcePool -ErrorAction Stop | Where-Object { $_.DisplayName -eq $target -or $_.Name -eq $target })
    }
    catch {
        $module.FailJson("Failed to query SCOM Resource Pools for '$target': $($_.Exception.Message)", $_)
    }

    if ($pools.Count -gt 0) {
        return $pools
    }

    $module.FailJson(
        "Target '$target' was not found as a SCOM Health Service computer or Resource Pool. " +
        "Valid targets are SCOM-managed agents, management servers, or resource pool display names."
    )
}


$spec = @{
    options = @{
        run_as_account = @{ type = "str"; required = $true }
        security_level = @{
            type = "str"
            required = $true
            choices = @("less_secure", "more_secure")
        }
        computers = @{ type = "list"; elements = "str"; required = $false; default = $null }
        append = @{ type = "bool"; required = $false; default = $true }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$run_as_account = $module.Params.run_as_account
$security_level = $module.Params.security_level
$computers = $module.Params.computers
$append = $module.Params.append

if (-not $append -and $null -eq $computers) {
    $module.FailJson(
        "'computers' is required when 'append' is false. " +
        "To clear all targets set 'computers: []' with 'append: false'. "
    )
}

$computers = if ($null -ne $computers) { $computers } else { @() }

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$account = $null
try {
    $account = Get-SCOMRunAsAccount -Name $run_as_account -ErrorAction Stop
}
catch {
    $module.FailJson("Failed to query SCOM RunAs account '$run_as_account': $($_.Exception.Message)", $_)
}

if ($null -eq $account) {
    $module.FailJson("No SCOM RunAs account found with name '$run_as_account'.")
}
if ($account -is [array] -and $account.Count -gt 1) {
    $module.FailJson("Multiple SCOM RunAs accounts found with name '$run_as_account'. The name must be unique.")
}

$distribution = $null
try {
    $distribution = Get-SCOMRunAsDistribution -RunAsAccount $account -ErrorAction Stop
}
catch {
    $module.FailJson("Failed to retrieve distribution for RunAs account '$run_as_account': $($_.Exception.Message)", $_)
}

$current_security = if ($null -ne $distribution) { [string]$distribution.Security } else { "" }
$current_computers = @(Get-DistributionComputerName -distribution $distribution)

$desired_security = (Get-SecurityLevelMap).AnsibleToSCOM[$security_level]

$desired_computers = @()
$distribution_objects = [System.Collections.Generic.List[object]]::new()
if ($security_level -eq "more_secure") {
    $target_names = if ($append) { @($current_computers + $computers) } else { @($computers) }
    $seen_display_names = @{}
    foreach ($name in @($target_names | Sort-Object -Unique)) {
        $resolved = Resolve-SCOMDistributionTarget -module $module -target $name
        foreach ($obj in @($resolved)) {
            $display_name = [string]$obj.DisplayName
            if (-not $seen_display_names.ContainsKey($display_name)) {
                $seen_display_names[$display_name] = $true
                $distribution_objects.Add($obj)
            }
        }
    }
    $desired_computers = @($seen_display_names.Keys | Sort-Object -Unique)
}

$needs_update = $false
if ($current_security -ne $desired_security) {
    $needs_update = $true
}
elseif ($security_level -eq "more_secure") {
    $diff = Compare-Object -ReferenceObject $current_computers -DifferenceObject $desired_computers
    if ($null -ne $diff) {
        $needs_update = $true
    }
}

if (-not $needs_update) {
    $module.Result.changed = $false
    $module.Result.distribution = @{
        run_as_account = $account.Name
        security_level = $security_level
        computers = $current_computers
    }
    $module.ExitJson()
}

$module.Result.changed = $true

if (-not $module.CheckMode) {
    try {
        if ($security_level -eq "less_secure") {
            Set-SCOMRunAsDistribution -RunAsAccount $account -LessSecure -ErrorAction Stop
        }
        else {
            Set-SCOMRunAsDistribution -RunAsAccount $account -MoreSecure -SecureDistribution $distribution_objects.ToArray() -ErrorAction Stop
        }
    }
    catch {
        $module.FailJson("Failed to set distribution for RunAs account '$run_as_account': $($_.Exception.Message)", $_)
    }

    try {
        $distribution = Get-SCOMRunAsDistribution -RunAsAccount $account -ErrorAction Stop
        $current_computers = @(Get-DistributionComputerName -distribution $distribution)
    }
    catch {
        $module.Warn("Distribution was updated but could not be re-fetched for result: $($_.Exception.Message)")
        $current_computers = $desired_computers
    }
}
else {
    $current_computers = $desired_computers
}

$module.Result.distribution = @{
    run_as_account = $account.Name
    security_level = $security_level
    computers = $current_computers
}

$module.ExitJson()
