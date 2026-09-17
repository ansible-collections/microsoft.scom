#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


Function Get-OverridePropertyName {
    <#
    Returns the effective property name for an override.
    Standard property overrides use .Property; configuration parameter overrides
    (e.g. Threshold) use .Parameter instead and leave .Property empty.
    #>
    param ([Parameter(Mandatory = $true)][object]$override)

    $prop = [string]$override.Property
    if (-not [string]::IsNullOrWhiteSpace($prop)) { return $prop }
    $param = [string]$override.Parameter
    if (-not [string]::IsNullOrWhiteSpace($param)) { return $param }
    return ""
}


Function ConvertTo-SdkValue {
    <#
    Converts the Ansible-style override_value (lowercase / snake_case) to the SDK string
    value expected by SCOM. Custom / numeric properties are returned unchanged.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$property,
        [Parameter(Mandatory = $true)][string]$value
    )

    switch ($property) {
        "AlertPriority" {
            switch ($value) {
                "low" { return "Low" }
                "normal" { return "Normal" }
                "high" { return "High" }
                default { return $value }
            }
        }
        "AlertSeverity" {
            switch ($value) {
                "information" { return "Information" }
                "warning" { return "Warning" }
                "error" { return "Error" }
                "match_monitor_health" { return "MatchMonitorHealth" }
                default { return $value }
            }
        }
        "AlertOnState" {
            switch ($value) {
                "error" { return "Error" }
                "warning" { return "Warning" }
                default { return $value }
            }
        }
        { $_ -in @("Enabled", "AutoResolve", "GenerateAlert") } {
            switch ($value.ToLower()) {
                "true" { return "True" }
                "false" { return "False" }
                default { return $value }
            }
        }
        default { return $value }
    }
}


Function Assert-CustomParameterValue {
    <#
    Validates override_value against the ParameterType string returned by
    $monitor.GetOverrideableParameters() (e.g. "int", "bool", "string").
    Calls $module.FailJson() immediately if the value cannot be converted.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$type_str,
        [Parameter(Mandatory = $true)][string]$property_name,
        [Parameter(Mandatory = $true)][string]$value,
        [Parameter(Mandatory = $true)][object]$module
    )

    if ([string]::IsNullOrWhiteSpace($type_str)) { return }

    switch ($type_str.ToLower()) {
        { $_ -in @("int", "int16", "int32", "int64", "uint16", "uint32", "uint64", "byte", "sbyte", "long") } {
            $dummy = 0L
            if (-not [long]::TryParse($value, [ref]$dummy)) {
                $module.FailJson(
                    "Invalid value '$value' for parameter '$property_name': " +
                    "expected an integer value (ParameterType: $type_str)."
                )
            }
        }
        { $_ -in @("float", "single", "double", "decimal") } {
            $dummy = 0.0
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $style = [System.Globalization.NumberStyles]::Any
            if (-not [double]::TryParse($value, $style, $culture, [ref]$dummy)) {
                $module.FailJson(
                    "Invalid value '$value' for parameter '$property_name': " +
                    "expected a numeric value (ParameterType: $type_str)."
                )
            }
        }
        { $_ -in @("bool", "boolean") } {
            if ($value.ToLower() -notin @("true", "false")) {
                $module.FailJson(
                    "Invalid value '$value' for parameter '$property_name': " +
                    "expected 'true' or 'false' (ParameterType: $type_str)."
                )
            }
        }
    }
}


Function Format-OverrideResult {
    <#
    Builds the result hashtable returned to the Ansible caller.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$monitor,
        [Parameter(Mandatory = $true)][string]$override_property,
        [Parameter(Mandatory = $true)][string]$override_value,
        [Parameter(Mandatory = $true)][string]$target,
        [Parameter(Mandatory = $true)][string]$target_name,
        [string]$management_pack = ""
    )

    return @{
        monitor_id = $monitor.Id.ToString()
        monitor_display_name = if ($null -ne $monitor.DisplayName) { [string]$monitor.DisplayName } else { "" }
        override_property = $override_property
        override_value = $override_value
        target = $target
        target_name = $target_name
        management_pack = $management_pack
    }
}


$spec = @{
    options = @{
        monitor_id = @{ type = "str"; required = $true }
        override_property = @{ type = "str"; required = $true }
        override_value = @{ type = "str"; required = $true }
        target = @{ type = "str"; required = $true; choices = @("class", "group") }
        target_name = @{ type = "str"; required = $true }
        management_pack = @{ type = "str"; required = $false; default = $null }
    }
    required_if = @(
        , @("override_property", "Enabled", @("management_pack"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$monitor_id = $module.Params.monitor_id
$override_property = $module.Params.override_property
$override_value = $module.Params.override_value
$target = $module.Params.target
$target_name = $module.Params.target_name
$management_pack = $module.Params.management_pack

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$monitor = $null
try {
    $monitor = @(Get-SCOMMonitor -Id ([System.Guid]$monitor_id) -ErrorAction SilentlyContinue)[0]
}
catch {
    $module.FailJson("Failed to query SCOM monitor '$monitor_id': $($_.Exception.Message)", $_)
}
if ($null -eq $monitor) {
    $module.FailJson("SCOM monitor with ID '$monitor_id' was not found.")
}

$system_params_enabled = @("Enabled")
$system_params_alert = @("GenerateAlert", "AutoResolve", "AlertPriority", "AlertSeverity", "AlertOnState")

$monitor_custom_param_objects = @()
$monitor_custom_params = @()
try {
    $monitor_custom_param_objects = @($monitor.GetOverrideableParameters())
    $monitor_custom_params = @($monitor_custom_param_objects | Select-Object -ExpandProperty Name)
}
catch {
    $null = $_  # GetOverrideableParameters() not available on all monitor types; fall through to empty list
}

$valid_properties = $system_params_enabled + $system_params_alert + $monitor_custom_params
if ($override_property -notin $valid_properties) {
    $module.FailJson(
        "'$override_property' is not a valid overrideable property for monitor '$($monitor.Name)'. " +
        "Valid properties: $($valid_properties -join ', ')"
    )
}

$normalized_value = $override_value.Trim().ToLower()

switch ($override_property) {
    "AlertPriority" {
        if ($normalized_value -notin @("low", "normal", "high")) {
            $module.FailJson(
                "Invalid value '$override_value' for 'AlertPriority'. " +
                "Valid values: low, normal, high"
            )
        }
    }
    "AlertSeverity" {
        if ($normalized_value -notin @("information", "warning", "error", "match_monitor_health")) {
            $module.FailJson(
                "Invalid value '$override_value' for 'AlertSeverity'. " +
                "Valid values: information, warning, error, match_monitor_health"
            )
        }
    }
    "AlertOnState" {
        if ($normalized_value -notin @("error", "warning")) {
            $module.FailJson(
                "Invalid value '$override_value' for 'AlertOnState'. " +
                "Valid values: error, warning"
            )
        }
    }
    { $_ -in @("AutoResolve", "GenerateAlert", "Enabled") } {
        if ($normalized_value -notin @("true", "false")) {
            $module.FailJson(
                "Invalid value '$override_value' for '$override_property'. " +
                "Valid values: true, false"
            )
        }
    }
}

if ($override_property -notin ($system_params_enabled + $system_params_alert) -and
    $override_property -in $monitor_custom_params) {
    $param_obj = $monitor_custom_param_objects |
        Where-Object { $_.Name -eq $override_property } |
        Select-Object -First 1
    if ($null -ne $param_obj) {
        $type_str = [string]$param_obj.ParameterType
        Assert-CustomParameterValue `
            -type_str      $type_str `
            -property_name $override_property `
            -value         $override_value `
            -module        $module
    }
}

$mp = $null
if ($null -ne $management_pack) {
    try {
        $mp = @(Get-SCOMManagementPack -Name $management_pack -ErrorAction SilentlyContinue)[0]
        if ($null -eq $mp) {
            $mp = @(Get-SCOMManagementPack -DisplayName $management_pack -ErrorAction SilentlyContinue)[0]
        }
    }
    catch {
        $module.FailJson("Failed to query management pack '$management_pack': $($_.Exception.Message)", $_)
    }
    if ($null -eq $mp) {
        $module.FailJson("Management pack '$management_pack' was not found by internal name or display name.")
    }
    if ($mp.Sealed) {
        $module.FailJson("Management pack '$management_pack' is sealed. Overrides must be stored in an unsealed management pack.")
    }
}

$target_class = $null
$target_group = $null

if ($target -eq "class" -and $target_name -ne "All Instances") {
    try {
        $target_class = @(Get-SCOMClass -DisplayName $target_name -ErrorAction SilentlyContinue)[0]
    }
    catch {
        $module.FailJson("Failed to query SCOM class '$target_name': $($_.Exception.Message)", $_)
    }
    if ($null -eq $target_class) {
        $module.FailJson("SCOM class with display name '$target_name' was not found.")
    }
}
elseif ($target -eq "group") {
    try {
        $target_group = @(Get-SCOMGroup -DisplayName $target_name -ErrorAction SilentlyContinue)[0]
    }
    catch {
        $module.FailJson("Failed to query SCOM group '$target_name': $($_.Exception.Message)", $_)
    }
    if ($null -eq $target_group) {
        $module.FailJson("SCOM group with display name '$target_name' was not found.")
    }
}

$all_overrides = @()
try {
    $all_overrides = @(Get-SCOMOverride -Monitor $monitor -ErrorAction Stop)
}
catch {
    $module.FailJson("Failed to retrieve overrides for monitor '$($monitor.Name)': $($_.Exception.Message)", $_)
}

$existing_override = $null
foreach ($ov in $all_overrides) {
    if ((Get-OverridePropertyName -override $ov) -ne $override_property) { continue }

    if ($target -eq "class" -and $target_name -eq "All Instances") {
        if ($null -eq $ov.Context -and $null -eq $ov.ContextInstance) {
            $existing_override = $ov
            break
        }
    }
    elseif ($target -eq "class" -and $null -ne $target_class) {
        if ($null -ne $ov.Context) {
            $ov_class = @(Get-SCOMClass -Id $ov.Context.Id -ErrorAction SilentlyContinue)[0]
            if ($null -ne $ov_class -and [string]$ov_class.DisplayName -eq $target_name) {
                $existing_override = $ov
                break
            }
        }
    }
    elseif ($target -eq "group" -and $null -ne $target_group) {
        if ($null -ne $ov.ContextInstance) {
            $ov_inst_id = if ($null -ne $ov.ContextInstance.Id) { $ov.ContextInstance.Id } else { $ov.ContextInstance }
            $ov_inst = @(Get-SCOMClassInstance -Id $ov_inst_id -ErrorAction SilentlyContinue)[0]
            if ($null -ne $ov_inst -and [string]$ov_inst.DisplayName -eq $target_name) {
                $existing_override = $ov
                break
            }
        }
        if ($null -eq $existing_override -and $null -ne $ov.Context) {
            $ov_ctx_class = @(Get-SCOMClass -Id $ov.Context.Id -ErrorAction SilentlyContinue)[0]
            if ($null -ne $ov_ctx_class -and [string]$ov_ctx_class.DisplayName -eq $target_name) {
                $existing_override = $ov
                break
            }
        }
    }
}

$sdk_value = ConvertTo-SdkValue -property $override_property -value $override_value
$scope_desc = if ($target_name -eq "All Instances") { "class-wide (All Instances)" } else { "$target '$target_name'" }

if ($null -eq $existing_override) {
    if ($override_property -ne "Enabled") {
        $module.FailJson(
            "Cannot change override value: no '$override_property' override is applied on monitor " +
            "'$($monitor.Name)' for $scope_desc. Apply the override first before modifying its value."
        )
    }
}
else {
    $current_value = [string]$existing_override.Value
    if ($current_value -ieq $sdk_value) {
        $module.Result.changed = $false
        $mp_display = ""
        if ($override_property -eq "Enabled") {
            $mp_display = if ($null -ne $mp.DisplayName) { [string]$mp.DisplayName } else { [string]$mp.Name }
        }
        else {
            try {
                $ov_mp = $existing_override.GetManagementPack()
                $mp_display = if (-not [string]::IsNullOrWhiteSpace($ov_mp.DisplayName)) { [string]$ov_mp.DisplayName } else { [string]$ov_mp.Name }
            }
            catch {
                $null = $_  # GetManagementPack() may fail; mp_display stays empty string
            }
        }
        $module.Result.override = Format-OverrideResult `
            -monitor $monitor `
            -override_property $override_property `
            -override_value $current_value `
            -target $target `
            -target_name $target_name `
            -management_pack $mp_display
        $module.ExitJson()
    }
}

$module.Result.changed = $true
if ($module.CheckMode) {
    $cm_mp_name = ""
    if ($override_property -eq "Enabled" -and $null -ne $mp) {
        $cm_mp_name = if (-not [string]::IsNullOrWhiteSpace($mp.DisplayName)) { [string]$mp.DisplayName } else { [string]$mp.Name }
    }
    elseif ($null -ne $existing_override) {
        try {
            $cm_ov_mp = $existing_override.GetManagementPack()
            $cm_mp_name = if (-not [string]::IsNullOrWhiteSpace($cm_ov_mp.DisplayName)) { [string]$cm_ov_mp.DisplayName } else { [string]$cm_ov_mp.Name }
        }
        catch {
            $null = $_  # GetManagementPack() may fail in check mode; cm_mp_name stays empty string
        }
    }

    $cm_current = if ($null -ne $existing_override) { [string]$existing_override.Value } else { "" }
    $module.Result.current_value = $cm_current
    $module.Result.override = Format-OverrideResult `
        -monitor $monitor `
        -override_property $override_property `
        -override_value $sdk_value `
        -target $target `
        -target_name $target_name `
        -management_pack $cm_mp_name
    $module.ExitJson()
}

$result_mp_name = ""

if ($override_property -eq "Enabled") {
    try {
        $want_enabled = ($sdk_value -eq "True")

        if ($target -eq "class" -and $target_name -eq "All Instances") {
            if ($want_enabled) { Enable-SCOMMonitor -Monitor $monitor -ManagementPack $mp -ErrorAction Stop }
            else { Disable-SCOMMonitor -Monitor $monitor -ManagementPack $mp -ErrorAction Stop }
        }
        elseif ($target -eq "class") {
            if ($want_enabled) { Enable-SCOMMonitor -Monitor $monitor -Class $target_class -ManagementPack $mp -ErrorAction Stop }
            else { Disable-SCOMMonitor -Monitor $monitor -Class $target_class -ManagementPack $mp -ErrorAction Stop }
        }
        else {
            if ($want_enabled) { Enable-SCOMMonitor -Monitor $monitor -Group $target_group -ManagementPack $mp -ErrorAction Stop }
            else { Disable-SCOMMonitor -Monitor $monitor -Group $target_group -ManagementPack $mp -ErrorAction Stop }
        }
    }
    catch {
        $verb = if ($sdk_value -eq "True") { "enable" } else { "disable" }
        $module.FailJson("Failed to $verb monitor '$($monitor.Name)': $($_.Exception.Message)", $_)
    }
    $result_mp_name = if ($null -ne $mp.DisplayName) { [string]$mp.DisplayName } else { [string]$mp.Name }
}
else {
    $override_mp = $null
    try {
        $override_mp = $existing_override.GetManagementPack()
    }
    catch {
        $module.FailJson(
            "Failed to resolve the management pack for the existing '$override_property' override: " +
            "$($_.Exception.Message)", $_
        )
    }
    if ($null -eq $override_mp) {
        $module.FailJson(
            "Cannot resolve the management pack for the existing '$override_property' override. " +
            "Ensure the override is stored in a resolvable unsealed management pack."
        )
    }

    $override_guid = $existing_override.Id
    $mp_owned_override = $override_mp.GetOverrides() | Where-Object { $_.Id -eq $override_guid } | Select-Object -First 1
    if ($null -eq $mp_owned_override) {
        $module.FailJson(
            "Could not locate override '$override_guid' inside management pack " +
            "'$($override_mp.Name)'. The override may have been removed."
        )
    }

    try {
        $mp_owned_override.Value = $sdk_value
        $mp_owned_override.Status = [Microsoft.EnterpriseManagement.Configuration.ManagementPackElementStatus]::PendingUpdate
        $override_mp.AcceptChanges()
    }
    catch {
        $module.FailJson(
            "Failed to update '$override_property' override on monitor '$($monitor.Name)': " +
            "$($_.Exception.Message)", $_
        )
    }
    $result_mp_name = if (-not [string]::IsNullOrWhiteSpace($override_mp.DisplayName)) { [string]$override_mp.DisplayName } else { [string]$override_mp.Name }
}

$module.Result.override = Format-OverrideResult `
    -monitor $monitor `
    -override_property $override_property `
    -override_value $sdk_value `
    -target $target `
    -target_name $target_name `
    -management_pack $result_mp_name

$module.ExitJson()
