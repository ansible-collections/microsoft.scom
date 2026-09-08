#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


Function Get-MPConfiguredMemberId {
    <#
    Reads the MonitoringObjectId GUIDs listed in the GroupPopulator DataSource
    configuration of the discovery rule embedded in the management pack.
    Available immediately after MP import - no GroupPopulator cycle needed.
    Returns an empty array when the discovery rule is absent or cannot be parsed.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$mp,
        [Parameter(Mandatory = $true)][string]$name
    )

    $result = @()
    try {
        $all_discoveries = @(Get-SCOMDiscovery -ManagementPack $mp -ErrorAction SilentlyContinue)
        $discovery = $all_discoveries |
            Where-Object { $_.Name -eq "$name.Group.DiscoveryRule" } |
            Select-Object -First 1

        if ($null -ne $discovery -and $null -ne $discovery.DataSource) {
            [xml]$config_xml = "<root>$($discovery.DataSource.Configuration)</root>"
            $nodes = @($config_xml.SelectNodes("//MonitoringObjectId"))
            $result = @($nodes | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ -ne "" })
        }
    }
    catch {
        Write-Verbose "Could not parse group discovery configuration for '$name': $($_.Exception.Message)"
    }

    return , $result
}



Function Update-GroupDiscovery {
    <#
    Modifies the group discovery's DataSource.Configuration XML in-place to reflect
    the new member list, then commits via AcceptChanges() and immediately triggers
    GroupPopulator via RefreshMonitoringGroupMembers() - no MP removal needed.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$mg,
        [Parameter(Mandatory = $true)][object]$mp,
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$member_ids
    )

    $discovery = $null
    try {
        $all_discoveries = @(Get-SCOMDiscovery -ManagementPack $mp -ErrorAction SilentlyContinue)
        $discovery = $all_discoveries |
            Where-Object { $_.Name -eq "$name.Group.DiscoveryRule" } |
            Select-Object -First 1
    }
    catch {
        $module.FailJson("Could not retrieve discovery rules for group '$name': $($_.Exception.Message)", $_)
    }
    if ($null -eq $discovery) {
        $module.FailJson("Discovery rule '$name.Group.DiscoveryRule' was not found in management pack '$name'.")
    }

    [xml]$config_xml = "<root>$($discovery.DataSource.Configuration)</root>"

    $entity_class = '$MPElement[Name="System!System.Entity"]$'
    $rel_class = '$MPElement[Name="MSIL!Microsoft.SystemCenter.InstanceGroupContainsEntities"]$'
    $new_rules = $config_xml.CreateElement("MembershipRules")

    if ($member_ids.Count -gt 0) {
        $rule_node = $config_xml.CreateElement("MembershipRule")
        $class_node = $config_xml.CreateElement("MonitoringClass")
        $class_node.InnerText = $entity_class
        [void]$rule_node.AppendChild($class_node)

        $rel_node = $config_xml.CreateElement("RelationshipClass")
        $rel_node.InnerText = $rel_class
        [void]$rule_node.AppendChild($rel_node)

        $include_node = $config_xml.CreateElement("IncludeList")
        foreach ($id in $member_ids) {
            $id_node = $config_xml.CreateElement("MonitoringObjectId")
            $id_node.InnerText = $id
            [void]$include_node.AppendChild($id_node)
        }
        [void]$rule_node.AppendChild($include_node)
        [void]$new_rules.AppendChild($rule_node)
    }

    $old_rules = $config_xml.root.MembershipRules
    if ($null -ne $old_rules) {
        [void]$config_xml.root.ReplaceChild($new_rules, $old_rules)
    }
    else {
        [void]$config_xml.root.AppendChild($new_rules)
    }

    try {
        $discovery.Status = [Microsoft.EnterpriseManagement.Configuration.ManagementPackElementStatus]::PendingUpdate
        $discovery.DataSource.Configuration = $config_xml.root.InnerXml.Trim()
        $updated_mp = $discovery.GetManagementPack()
        [void]$updated_mp.AcceptChanges()
    }
    catch {
        $inner = if ($null -ne $_.Exception.InnerException) { " Inner: $($_.Exception.InnerException.Message)" } else { "" }
        $module.FailJson("Failed to commit group membership update for '$name': $($_.Exception.Message)$inner", $_)
    }

    try {
        [void]$mg.RefreshMonitoringGroupMembers($updated_mp)
    }
    catch {
        Write-Verbose "RefreshMonitoringGroupMembers failed for '$name': $($_.Exception.Message)"
    }

    return $updated_mp
}


Function Invoke-GroupPopulatorRefresh {
    <#
    Calls RefreshMonitoringGroupMembers() on a freshly imported management pack to
    trigger GroupPopulator immediately instead of waiting for its scheduled cycle.
    Best-effort: silently ignored when the method is unavailable.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$mg,
        [Parameter(Mandatory = $true)][string]$name
    )

    try {
        $mp = Get-SCOMManagementPack -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $mp) {
            [void]$mg.RefreshMonitoringGroupMembers($mp)
        }
    }
    catch {
        Write-Verbose "GroupPopulator refresh failed for '$name': $($_.Exception.Message)"
    }
}


Function Format-GroupResult {
    <#
    Builds the return hashtable for a SCOM group.
    - configured_members: GUIDs stored in the MP XML (always present immediately after import or update).
    - members: runtime objects from GetRelatedMonitoringObjects()
    #>
    param (
        [Parameter(Mandatory = $true)][object]$group,
        [Parameter(Mandatory = $true)][string]$management_pack,
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][string[]]$configured_member_ids = @()
    )

    $configured_members = @($configured_member_ids | ForEach-Object { @{ id = $_ } })

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
        management_pack = $management_pack
        configured_members = $configured_members
        members = $members.ToArray()
    }
}


Function New-GroupManagementPackXml {
    <#
    Builds the management pack XML that defines a SCOM instance group with explicit
    (static) membership. Each member is identified by its monitoring object GUID.
    Members can be any SCOM monitoring object type (computers, IIS sites, health
    services, etc.). An empty members list creates an empty group.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$identity,
        [Parameter(Mandatory = $true)][string]$display_name,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$members
    )

    $class_id = "$identity.Group"
    $escaped_display = [System.Security.SecurityElement]::Escape($display_name)
    $entity_class = '$MPElement[Name="System!System.Entity"]$'
    $relationship_class = '$MPElement[Name="MSIL!Microsoft.SystemCenter.InstanceGroupContainsEntities"]$'
    $rule_id = '$MPElement$'
    $group_instance_id = "`$MPElement[Name=`"$class_id`"]`$"

    if ($members.Count -eq 0) {
        $membership_rules_block = "          <MembershipRules />"
    }
    else {
        $include_id_lines = $members | ForEach-Object {
            "                <MonitoringObjectId>$_</MonitoringObjectId>"
        }
        $include_ids = $include_id_lines -join "`n"
        $membership_rules_block = @"
          <MembershipRules>
            <MembershipRule>
              <MonitoringClass>$entity_class</MonitoringClass>
              <RelationshipClass>$relationship_class</RelationshipClass>
              <IncludeList>
$include_ids
              </IncludeList>
            </MembershipRule>
          </MembershipRules>
"@
    }

    return @"
<ManagementPack ContentReadable="true" SchemaVersion="2.0" OriginalSchemaVersion="1.1"
                xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <Manifest>
    <Identity>
      <ID>$identity</ID>
      <Version>1.0.0.0</Version>
    </Identity>
    <Name>$escaped_display</Name>
    <References>
      <Reference Alias="System">
        <ID>System.Library</ID>
        <Version>7.5.8501.1</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="SC">
        <ID>Microsoft.SystemCenter.Library</ID>
        <Version>10.22.10118.0</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
      <Reference Alias="MSIL">
        <ID>Microsoft.SystemCenter.InstanceGroup.Library</ID>
        <Version>7.5.8501.1</Version>
        <PublicKeyToken>31bf3856ad364e35</PublicKeyToken>
      </Reference>
    </References>
  </Manifest>
  <TypeDefinitions>
    <EntityTypes>
      <ClassTypes>
        <ClassType ID="$class_id" Accessibility="Public" Abstract="false"
                   Base="MSIL!Microsoft.SystemCenter.InstanceGroup"
                   Hosted="false" Singleton="true" Extension="false" />
      </ClassTypes>
    </EntityTypes>
  </TypeDefinitions>
  <Monitoring>
    <Discoveries>
      <Discovery ID="$class_id.DiscoveryRule" Enabled="true" Target="$class_id" ConfirmDelivery="false" Remotable="true" Priority="Normal">
        <Category>Discovery</Category>
        <DiscoveryTypes>
          <DiscoveryRelationship TypeID="MSIL!Microsoft.SystemCenter.InstanceGroupContainsEntities" />
        </DiscoveryTypes>
        <DataSource ID="GroupPopulationDataSource" TypeID="SC!Microsoft.SystemCenter.GroupPopulator">
          <RuleId>$rule_id</RuleId>
          <GroupInstanceId>$group_instance_id</GroupInstanceId>
$membership_rules_block
        </DataSource>
      </Discovery>
    </Discoveries>
  </Monitoring>
  <LanguagePacks>
    <LanguagePack ID="ENU" IsDefault="true">
      <DisplayStrings>
        <DisplayString ElementID="$class_id"><Name>$escaped_display</Name></DisplayString>
      </DisplayStrings>
    </LanguagePack>
  </LanguagePacks>
</ManagementPack>
"@
}


Function Resolve-SCOMMemberId {
    <#
    Resolves the 'members' list to a list of monitoring object GUIDs.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$members
    )

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($member in $members) {
        $parsed = [System.Guid]::Empty
        if ([System.Guid]::TryParse($member, [ref]$parsed)) {
            $resolved.Add($parsed.ToString())
            continue
        }

        $instances = @()
        try {
            $instances = @(Get-SCOMClassInstance -DisplayName $member -ErrorAction SilentlyContinue)
        }
        catch {
            $module.FailJson("Failed to resolve member '$member' by display name: $($_.Exception.Message)", $_)
        }

        if ($instances.Count -eq 0) {
            $module.FailJson("Member '$member' does not exist in SCOM.")
        }

        $unique_ids = @(
            $instances |
                Where-Object { $null -ne $_.Id } |
                ForEach-Object { $_.Id.ToString() } |
                Sort-Object -Unique
        )

        if ($unique_ids.Count -eq 0) {
            $module.FailJson("Member '$member' does not exist in SCOM.")
        }

        if ($unique_ids.Count -gt 1) {
            $module.Warn(
                "Member '$member' resolved to $($unique_ids.Count) distinct monitoring object IDs " +
                "(same display name, different class instances). Using the first one ($($unique_ids[0])). " +
                "Supply the GUID directly if you need a specific class instance."
            )
        }

        $resolved.Add($unique_ids[0])
    }

    return , $resolved.ToArray()
}


$spec = @{
    options = @{
        name = @{ type = "str"; required = $true }
        display_name = @{ type = "str"; required = $false; default = $null }
        members = @{ type = "list"; elements = "str"; required = $false; default = @() }
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$display_name = if ($null -ne $module.Params.display_name) { $module.Params.display_name } else { $name }
$members = $module.Params.members
$state = $module.Params.state

if (-not (Test-SCOMManagementPackIdentifier -value $name)) {
    $module.FailJson(
        "The 'name' parameter '$name' is not a valid SCOM internal name. " +
        "It must start with a letter or underscore and contain only letters, digits, " +
        "underscores, and dots (no spaces)."
    )
}

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$mg = $null
try {
    $mg = Get-SCOMManagementGroup -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "Could not retrieve management group: $($_.Exception.Message)"
}

$existing_mp = $null
try {
    $existing_mp = Get-SCOMManagementPack -Name $name -ErrorAction SilentlyContinue
}
catch {
    $module.FailJson("Failed to query SCOM management pack '$name': $($_.Exception.Message)", $_)
}

if ($state -eq "absent") {
    if ($null -eq $existing_mp) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $null = $existing_mp | Remove-SCOMManagementPack -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM group management pack '$name': $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}

$member_ids = Resolve-SCOMMemberId -module $module -members $members

# state == present
if ($null -ne $existing_mp) {
    $configured_ids = Get-MPConfiguredMemberId -mp $existing_mp -name $name

    $requested_norm = @($member_ids | ForEach-Object { $_.ToLower() } | Sort-Object -Unique)
    $configured_norm = @($configured_ids | ForEach-Object { $_.ToLower() } | Sort-Object -Unique)
    $added = @($requested_norm | Where-Object { $configured_norm -notcontains $_ })
    $removed = @($configured_norm | Where-Object { $requested_norm -notcontains $_ })

    if ($added.Count -eq 0 -and $removed.Count -eq 0) {
        $module.Result.changed = $false
        $group = @(Get-SCOMGroup -DisplayName $display_name -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($null -ne $group) {
            $module.Result.group = Format-GroupResult `
                -group                $group `
                -management_pack      $name `
                -configured_member_ids $configured_ids
        }
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        $existing_mp = Update-GroupDiscovery `
            -module     $module `
            -mg         $mg `
            -mp         $existing_mp `
            -name       $name `
            -member_ids $member_ids
    }

    $group = @(Get-SCOMGroup -DisplayName $display_name -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($null -ne $group) {
        $module.Result.group = Format-GroupResult `
            -group                $group `
            -management_pack      $name `
            -configured_member_ids $member_ids
    }
    $module.ExitJson()
}

# create new MP
$module.Result.changed = $true

if (-not $module.CheckMode) {
    $xml_path = Join-Path -Path $env:TEMP -ChildPath "$name.xml"
    $xml = New-GroupManagementPackXml -identity $name -display_name $display_name -members $member_ids

    try {
        Set-Content -LiteralPath $xml_path -Value $xml -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $module.FailJson("Failed to write the group management pack file '$xml_path': $($_.Exception.Message)", $_)
    }

    try {
        Import-SCOMManagementPack -FullName $xml_path -ErrorAction Stop *> $null
    }
    catch {
        $inner = if ($null -ne $_.Exception.InnerException) { " Inner: $($_.Exception.InnerException.Message)" } else { "" }
        $module.FailJson("Failed to import the group management pack '$name': $($_.Exception.Message)$inner", $_)
    }
    finally {
        Remove-Item -LiteralPath $xml_path -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $mg) {
        Invoke-GroupPopulatorRefresh -mg $mg -name $name
    }

    $group = @(Get-SCOMGroup -DisplayName $display_name -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($null -ne $group) {
        $module.Result.group = Format-GroupResult `
            -group                $group `
            -management_pack      $name `
            -configured_member_ids $member_ids
    }
}

$module.ExitJson()
