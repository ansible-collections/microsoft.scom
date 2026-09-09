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
        # Use $mp.GetDiscoveries() (direct SDK method on the ManagementPack object) rather
        # than Get-SCOMDiscovery -ManagementPack, which does not surface discoveries from
        # SDK-imported management packs reliably.
        $all_discoveries = @($mp.GetDiscoveries())
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
        $all_discoveries = @($mp.GetDiscoveries())
        $discovery = $all_discoveries |
            Where-Object { $_.Name -eq "$name.Group.DiscoveryRule" } |
            Select-Object -First 1
    }
    catch {
        $module.FailJson("Could not retrieve discovery rules for group '$name': $($_.Exception.Message)", $_)
    }
    if ($null -eq $discovery) {
        $module.FailJson(
            "Discovery rule '$name.Group.DiscoveryRule' was not found in management pack '$name'. " +
            "Available discoveries: $((@($mp.GetDiscoveries()) | ForEach-Object { $_.Name }) -join ', ')"
        )
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


Function New-GroupManagementPack {
    <#
    Creates a SCOM instance group management pack
    The full management pack XML is constructed via XmlDocument DOM.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $true)][string]$display_name,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$member_ids
    )

    $all_installed = @(Get-SCOMManagementPack -ErrorAction SilentlyContinue)
    $system_lib = $all_installed |
        Where-Object { $_.Name -eq "System.Library" } |
        Select-Object -First 1
    $sc_lib = $all_installed |
        Where-Object { $_.Name -eq "Microsoft.SystemCenter.Library" } |
        Select-Object -First 1
    $msil_lib = $all_installed |
        Where-Object { $_.Name -eq "Microsoft.SystemCenter.InstanceGroup.Library" } |
        Select-Object -First 1

    $lib_checks = @(
        @{ Name = "System.Library"; Mp = $system_lib },
        @{ Name = "Microsoft.SystemCenter.Library"; Mp = $sc_lib },
        @{ Name = "Microsoft.SystemCenter.InstanceGroup.Library"; Mp = $msil_lib }
    )
    foreach ($check in $lib_checks) {
        if ($null -eq $check.Mp) {
            $module.FailJson(
                "Required SCOM library '$($check.Name)' is not installed in this management group. " +
                "Ensure all required base management packs are present before creating groups."
            )
        }
    }

    $class_id = "$name.Group"

    $schema_version = "2.0"
    $orig_schema_version = "1.1"
    $unsealed_mp = $all_installed | Where-Object { -not $_.Sealed } | Select-Object -First 1
    if ($null -ne $unsealed_mp) {
        try {
            [xml]$ref_xml = $unsealed_mp.GetManagementPackXml()
            if ($null -ne $ref_xml.ManagementPack.SchemaVersion) {
                $schema_version = $ref_xml.ManagementPack.SchemaVersion
            }
            if ($null -ne $ref_xml.ManagementPack.OriginalSchemaVersion) {
                $orig_schema_version = $ref_xml.ManagementPack.OriginalSchemaVersion
            }
        }
        catch {
            Write-Verbose "Could not read schema version from existing MP '$($unsealed_mp.Name)': $($_.Exception.Message). Using defaults."
        }
    }

    [System.Xml.XmlDocument]$doc = [System.Xml.XmlDocument]::new()

    $root = $doc.CreateElement("ManagementPack")
    $root.SetAttribute("ContentReadable", "true")
    $root.SetAttribute("SchemaVersion", $schema_version)
    $root.SetAttribute("OriginalSchemaVersion", $orig_schema_version)
    $root.SetAttribute("xmlns:xsd", "http://www.w3.org/2001/XMLSchema")
    $root.SetAttribute("xmlns:xsl", "http://www.w3.org/1999/XSL/Transform")
    [void]$doc.AppendChild($root)

    # <Manifest>
    $manifest = $doc.CreateElement("Manifest")
    [void]$root.AppendChild($manifest)

    $identity_el = $doc.CreateElement("Identity")
    [void]$manifest.AppendChild($identity_el)
    $id_el = $doc.CreateElement("ID")
    $id_el.InnerText = $name
    [void]$identity_el.AppendChild($id_el)
    $ver_el = $doc.CreateElement("Version")
    $ver_el.InnerText = "1.0.0.0"
    [void]$identity_el.AppendChild($ver_el)

    $mp_name_el = $doc.CreateElement("Name")
    $mp_name_el.InnerText = $display_name
    [void]$manifest.AppendChild($mp_name_el)

    $references_el = $doc.CreateElement("References")
    [void]$manifest.AppendChild($references_el)

    $ref_items = @(
        @{ Alias = "System"; Mp = $system_lib },
        @{ Alias = "SC"; Mp = $sc_lib },
        @{ Alias = "MSIL"; Mp = $msil_lib }
    )
    foreach ($ref_info in $ref_items) {
        $ref_el = $doc.CreateElement("Reference")
        $ref_el.SetAttribute("Alias", $ref_info.Alias)
        $ref_id_el = $doc.CreateElement("ID")
        $ref_id_el.InnerText = $ref_info.Mp.Name
        [void]$ref_el.AppendChild($ref_id_el)
        $ref_ver_el = $doc.CreateElement("Version")
        $ref_ver_el.InnerText = $ref_info.Mp.Version.ToString()
        [void]$ref_el.AppendChild($ref_ver_el)
        $ref_token_el = $doc.CreateElement("PublicKeyToken")
        $ref_token_el.InnerText = if ($null -ne $ref_info.Mp.KeyToken -and $ref_info.Mp.KeyToken -ne "") {
            $ref_info.Mp.KeyToken
        }
        else { "null" }
        [void]$ref_el.AppendChild($ref_token_el)
        [void]$references_el.AppendChild($ref_el)
    }

    # <TypeDefinitions>
    $typedef_el = $doc.CreateElement("TypeDefinitions")
    [void]$root.AppendChild($typedef_el)
    $entity_types_el = $doc.CreateElement("EntityTypes")
    [void]$typedef_el.AppendChild($entity_types_el)
    $class_types_el = $doc.CreateElement("ClassTypes")
    [void]$entity_types_el.AppendChild($class_types_el)

    $class_type_el = $doc.CreateElement("ClassType")
    $class_type_el.SetAttribute("ID", $class_id)
    $class_type_el.SetAttribute("Accessibility", "Public")
    $class_type_el.SetAttribute("Abstract", "false")
    $class_type_el.SetAttribute("Base", "MSIL!Microsoft.SystemCenter.InstanceGroup")
    $class_type_el.SetAttribute("Hosted", "false")
    $class_type_el.SetAttribute("Singleton", "true")
    $class_type_el.SetAttribute("Extension", "false")
    [void]$class_types_el.AppendChild($class_type_el)

    # <Monitoring>
    $monitoring_el = $doc.CreateElement("Monitoring")
    [void]$root.AppendChild($monitoring_el)
    $discoveries_el = $doc.CreateElement("Discoveries")
    [void]$monitoring_el.AppendChild($discoveries_el)

    $discovery_el = $doc.CreateElement("Discovery")
    $discovery_el.SetAttribute("ID", "$class_id.DiscoveryRule")
    $discovery_el.SetAttribute("Enabled", "true")
    $discovery_el.SetAttribute("Target", $class_id)
    $discovery_el.SetAttribute("ConfirmDelivery", "false")
    $discovery_el.SetAttribute("Remotable", "true")
    $discovery_el.SetAttribute("Priority", "Normal")
    [void]$discoveries_el.AppendChild($discovery_el)

    $category_el = $doc.CreateElement("Category")
    $category_el.InnerText = "Discovery"
    [void]$discovery_el.AppendChild($category_el)

    $disc_types_el = $doc.CreateElement("DiscoveryTypes")
    [void]$discovery_el.AppendChild($disc_types_el)
    $disc_rel_el = $doc.CreateElement("DiscoveryRelationship")
    $disc_rel_el.SetAttribute("TypeID", "MSIL!Microsoft.SystemCenter.InstanceGroupContainsEntities")
    [void]$disc_types_el.AppendChild($disc_rel_el)

    $datasource_el = $doc.CreateElement("DataSource")
    $datasource_el.SetAttribute("ID", "GroupPopulationDataSource")
    $datasource_el.SetAttribute("TypeID", "SC!Microsoft.SystemCenter.GroupPopulator")
    [void]$discovery_el.AppendChild($datasource_el)

    $rule_id_node = $doc.CreateElement("RuleId")
    $rule_id_node.InnerText = '$MPElement$'
    [void]$datasource_el.AppendChild($rule_id_node)

    $group_instance_id_node = $doc.CreateElement("GroupInstanceId")
    $group_instance_id_node.InnerText = '$MPElement[Name="' + $class_id + '"]$'
    [void]$datasource_el.AppendChild($group_instance_id_node)

    $membership_rules_node = $doc.CreateElement("MembershipRules")
    if ($member_ids.Count -gt 0) {
        $rule_node = $doc.CreateElement("MembershipRule")

        $class_node = $doc.CreateElement("MonitoringClass")
        $class_node.InnerText = '$MPElement[Name="System!System.Entity"]$'
        [void]$rule_node.AppendChild($class_node)

        $rel_node = $doc.CreateElement("RelationshipClass")
        $rel_node.InnerText = '$MPElement[Name="MSIL!Microsoft.SystemCenter.InstanceGroupContainsEntities"]$'
        [void]$rule_node.AppendChild($rel_node)

        $include_node = $doc.CreateElement("IncludeList")
        foreach ($id in $member_ids) {
            $id_node = $doc.CreateElement("MonitoringObjectId")
            $id_node.InnerText = $id
            [void]$include_node.AppendChild($id_node)
        }
        [void]$rule_node.AppendChild($include_node)
        [void]$membership_rules_node.AppendChild($rule_node)
    }
    [void]$datasource_el.AppendChild($membership_rules_node)

    # <LanguagePacks>
    $lang_packs_el = $doc.CreateElement("LanguagePacks")
    [void]$root.AppendChild($lang_packs_el)
    $lang_pack_el = $doc.CreateElement("LanguagePack")
    $lang_pack_el.SetAttribute("ID", "ENU")
    $lang_pack_el.SetAttribute("IsDefault", "true")
    [void]$lang_packs_el.AppendChild($lang_pack_el)
    $display_strings_el = $doc.CreateElement("DisplayStrings")
    [void]$lang_pack_el.AppendChild($display_strings_el)
    $display_string_el = $doc.CreateElement("DisplayString")
    $display_string_el.SetAttribute("ElementID", $class_id)
    [void]$display_strings_el.AppendChild($display_string_el)
    $ds_name_el = $doc.CreateElement("Name")
    $ds_name_el.InnerText = $display_name
    [void]$display_string_el.AppendChild($ds_name_el)

    $xml_path = [System.IO.Path]::Combine($env:TEMP, "$name.xml")

    try {
        $doc.Save($xml_path)
    }
    catch {
        $module.FailJson("Failed to write management pack file '$xml_path': $($_.Exception.Message)", $_)
    }

    try {
        Import-SCOMManagementPack -FullName $xml_path -ErrorAction Stop *> $null
    }
    catch {
        $inner = if ($null -ne $_.Exception.InnerException) {
            " Inner: $($_.Exception.InnerException.Message)"
        }
        else { "" }
        $module.FailJson(
            "Failed to import the group management pack '$name': $($_.Exception.Message)$inner", $_)
    }
    finally {
        Remove-Item -LiteralPath $xml_path -Force -ErrorAction SilentlyContinue
    }
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
    $existing_discoveries = @($existing_mp.GetDiscoveries() | ForEach-Object { $_.Name })
    if ($existing_discoveries -notcontains "$name.Group.DiscoveryRule") {
        $module.Warn(
            "Management pack '$name' exists but is missing the expected discovery rule " +
            "'$name.Group.DiscoveryRule' (found: '$($existing_discoveries -join "', '")'). " +
            "The pack will be removed and recreated to restore a consistent state."
        )
        $module.Result.changed = $true
        if (-not $module.CheckMode) {
            try {
                $null = $existing_mp | Remove-SCOMManagementPack -ErrorAction Stop
            }
            catch {
                $module.FailJson(
                    "Management pack '$name' is structurally incomplete (missing discovery rule) " +
                    "and could not be removed for recreation: $($_.Exception.Message)", $_)
            }
        }
        $existing_mp = $null
    }
}

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
    New-GroupManagementPack `
        -module       $module `
        -name         $name `
        -display_name $display_name `
        -member_ids   $member_ids

    Invoke-GroupPopulatorRefresh -mg $mg -name $name

    $group = @(Get-SCOMGroup -DisplayName $display_name -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($null -ne $group) {
        $module.Result.group = Format-GroupResult `
            -group                $group `
            -management_pack      $name `
            -configured_member_ids $member_ids
    }
}

$module.ExitJson()
