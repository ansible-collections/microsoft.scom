# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# Shared utilities for the run_as_distribution and run_as_distribution_info modules.


Function Get-DistributionComputerName {
    <#
    .SYNOPSIS
    Returns the sorted list of display names of all targets in a RunAs account's
    secure distribution, or an empty array when nothing is distributed.

    .DESCRIPTION
    Iterates SecureDistribution and collects each target's DisplayName (falling back to
    Name when DisplayName is null). The result includes both Health Service objects
    (computers / management servers) and Resource Pool objects.

    .PARAMETER distribution
    The SCOMRunAsDistribution object returned by Get-SCOMRunAsDistribution, or $null.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$distribution
    )

    if ($null -eq $distribution -or $null -eq $distribution.SecureDistribution) {
        return @()
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $distribution.SecureDistribution) {
        if ($null -ne $target.DisplayName) {
            $names.Add([string]$target.DisplayName)
        }
        elseif ($null -ne $target.Name) {
            $names.Add([string]$target.Name)
        }
    }

    return ($names | Sort-Object -Unique)
}


Function Get-SecurityLevelMap {
    <#
    .SYNOPSIS
    Returns both security level mapping directions for RunAs distribution.

    .DESCRIPTION
    Wraps the maps in a function because module-level variables in psm1 files are not
    exported to the calling script when Ansible dot-sources the utility file.

    Usage:
      (Get-SecurityLevelMap).AnsibleToSCOM[$security_level]       # "less_secure" -> "LessSecure"
      (Get-SecurityLevelMap).SCOMToAnsible[[string]$dist.Security] # "LessSecure" -> "less_secure"
    #>
    return @{
        AnsibleToSCOM = @{ less_secure = "LessSecure"; more_secure = "MoreSecure" }
        SCOMToAnsible = @{ LessSecure = "less_secure"; MoreSecure = "more_secure" }
    }
}
