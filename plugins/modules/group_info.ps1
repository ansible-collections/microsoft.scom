#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


Function Get-GroupConfiguredMemberId {
    <#
    Reads the MonitoringObjectId GUIDs from the management pack that defines this
    group. The MP name is derived by stripping the trailing '.Group' suffix from
    the group's FullName (the convention used by the microsoft.scom.group module).
    Returns an empty array for built-in or third-party groups whose MP cannot be
    found or whose DataSource configuration cannot be parsed.
    Available immediately - no GroupPopulator cycle needed.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$group
    )

    try {
        $full_name = [string]$group.FullName
        if (-not $full_name.EndsWith('.Group')) { return , @() }
        $mp_name = $full_name -replace '\.Group$', ''

        $mp = Get-SCOMManagementPack -Name $mp_name -ErrorAction SilentlyContinue
        if ($null -eq $mp) { return , @() }

        $all_discoveries = @(Get-SCOMDiscovery -ManagementPack $mp -ErrorAction SilentlyContinue)
        $discovery = $all_discoveries |
            Where-Object { $_.Name -eq "$mp_name.Group.DiscoveryRule" } |
            Select-Object -First 1
        if ($null -eq $discovery -or $null -eq $discovery.DataSource) { return , @() }

        [xml]$config_xml = "<root>$($discovery.DataSource.Configuration)</root>"
        return , @(
            $config_xml.SelectNodes("//MonitoringObjectId") |
                ForEach-Object { $_.InnerText.Trim() } |
                Where-Object { $_ -ne "" }
        )
    }
    catch {
        return , @()
    }
}


Function Format-GroupResult {
    <#
    Builds the return hashtable for a SCOM group.
    - configured_members: GUIDs from the management pack XML (always consistent,
      available immediately after import/update before GroupPopulator runs).
    - members: runtime objects from GetRelatedMonitoringObjects() (populated only
      after GroupPopulator has run - may be empty for recently created groups).
    #>
    param (
        [Parameter(Mandatory = $true)][object]$group
    )

    $configured_ids = Get-GroupConfiguredMemberId -group $group
    $configured_members = @($configured_ids | ForEach-Object { @{ id = $_ } })

    $members = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($m in @($group.GetRelatedMonitoringObjects() 2>$null)) {
        if ($null -eq $m) { continue }
        $member_entry = @{
            display_name = if ($null -ne $m.DisplayName) { [string]$m.DisplayName } else { "" }
            name = if ($null -ne $m.Name) { [string]$m.Name } else { "" }
            id = if ($null -ne $m.Id) { $m.Id.ToString() } else { "" }
        }
        $members.Add($member_entry)
    }

    return @{
        name = [string]$group.FullName
        display_name = if ($null -ne $group.DisplayName) { [string]$group.DisplayName } else { "" }
        full_name = [string]$group.FullName
        id = if ($null -ne $group.Id) { $group.Id.ToString() } else { "" }
        configured_members = $configured_members
        members = $members.ToArray()
    }
}


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

$groups = @()
try {
    if ($null -ne $display_name) {
        $groups = @(Get-SCOMGroup -DisplayName $display_name -ErrorAction Stop)
    }
    elseif ($null -ne $name) {
        $groups = @(Get-SCOMGroup -ErrorAction Stop | Where-Object { [string]$_.FullName -eq $name })
    }
    else {
        $groups = @(Get-SCOMGroup -ErrorAction Stop)
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM groups: $($_.Exception.Message)", $_)
}

$result_groups = [System.Collections.Generic.List[hashtable]]::new()
foreach ($group in $groups) {
    if ($null -eq $group) { continue }
    $result_groups.Add((Format-GroupResult -group $group))
}

$module.Result.changed = $false
$module.Result.groups = $result_groups.ToArray()

$module.ExitJson()
