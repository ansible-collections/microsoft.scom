#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


Function Get-TargetClassDisplayName {
    <#
    Best-effort resolution of the target class display name for a monitor.
    Returns an empty string when the class cannot be resolved.
    #>
    param ([Parameter(Mandatory = $true)][object]$monitor)

    try {
        if ($null -ne $monitor.Target -and $null -ne $monitor.Target.Id) {
            $class = Get-SCOMClass -Id $monitor.Target.Id -ErrorAction SilentlyContinue
            if ($null -ne $class) { return [string]$class.DisplayName }
        }
    }
    catch {
        $null = $_  # Target class lookup may fail; fall through to empty string
    }
    return ""
}


Function Get-MonitorManagementPackDisplayName {
    <#
    Best-effort resolution of the management pack display name for a monitor.
    Falls back to the raw ManagementPackName property when GetManagementPack() fails.
    #>
    param ([Parameter(Mandatory = $true)][object]$monitor)

    try {
        $mp = $monitor.GetManagementPack()
        if ($null -ne $mp) { return [string]$mp.DisplayName }
    }
    catch {
        $null = $_  # GetManagementPack() may fail; fall back to ManagementPackName property
    }
    return [string]$monitor.ManagementPackName
}


Function Get-OverrideManagementPackDisplayName {
    <#
    Resolves the display name of the management pack that stores an override.
    Three methods are attempted in order because certain override types (e.g. Enabled
    overrides) may return $null or an object with an empty DisplayName from the first
    method, requiring a fallback to reach the management pack name:
      A. GetManagementPack() SDK call         — works for most override types; may return
                                                $null or empty DisplayName for some (e.g. Enabled).
      B. .ManagementPack.DisplayName / .Name  — fallback when Method A returns an unusable object.
      C. Get-SCOMManagementPack -Id           — last resort when the MP object is null but the
                                                MP Id is still accessible for a fresh lookup.
    Returns "Unknown" when none of the three methods produce a usable name.
    #>
    param ([Parameter(Mandatory = $true)][object]$override)

    # Method A: May return $null for some override types
    try {
        $mp = $override.GetManagementPack()
        if ($null -ne $mp -and -not [string]::IsNullOrWhiteSpace($mp.DisplayName)) {
            return [string]$mp.DisplayName
        }
    }
    catch {
        $null = $_
    }

    # Method B: Used when Method A returns $null or an object whose DisplayName is empty.
    try {
        if ($null -ne $override.ManagementPack) {
            if (-not [string]::IsNullOrWhiteSpace($override.ManagementPack.DisplayName)) {
                return [string]$override.ManagementPack.DisplayName
            }
            if (-not [string]::IsNullOrWhiteSpace($override.ManagementPack.Name)) {
                return [string]$override.ManagementPack.Name
            }
        }
    }
    catch {
        $null = $_
    }

    # Method C: Explicit query by management pack Id.
    try {
        if ($null -ne $override.ManagementPack -and $null -ne $override.ManagementPack.Id) {
            $mp = Get-SCOMManagementPack -Id $override.ManagementPack.Id -ErrorAction SilentlyContinue
            if ($null -ne $mp -and -not [string]::IsNullOrWhiteSpace($mp.DisplayName)) {
                return [string]$mp.DisplayName
            }
        }
    }
    catch {
        $null = $_
    }

    return "Unknown"
}


Function Get-OverridePropertyName {
    <#
    Resolves the name of the monitor property being overridden.
    Standard property overrides populate .Property (e.g. Enabled, AlertPriority).
    Configuration parameter overrides (e.g. Threshold, IntervalSeconds on some monitor
    types) populate .Parameter instead and leave .Property empty.
    Returns "Unknown" when neither field contains a value.
    #>
    param ([Parameter(Mandatory = $true)][object]$override)

    $property = [string]$override.Property
    if (-not [string]::IsNullOrWhiteSpace($property)) { return $property }
    $parameter = [string]$override.Parameter
    if (-not [string]::IsNullOrWhiteSpace($parameter)) { return $parameter }
    return "Unknown"
}


Function Get-OverrideScopeInfo {
    <#
    Resolves the scope an override acts on and the display name of that scope target.

    Returns a hashtable with two keys:
      override_scope - one of "Class", "Group", or "Object/Instance"
      target_name    - the display name of the scope target, or "All Instances" when the
                       override applies to the whole target class with no further restriction.
    #>
    param ([Parameter(Mandatory = $true)][object]$override)

    $scope_type = "Class"
    $target_name = "All Instances"

    try {
        if ($null -ne $override.ContextInstance) {
            # Scoped to a specific object or group instance.
            $instance_id = if ($null -ne $override.ContextInstance.Id) { $override.ContextInstance.Id } else { $override.ContextInstance }
            $instance = Get-SCOMClassInstance -Id $instance_id -ErrorAction SilentlyContinue

            if ($null -ne $instance) {
                $target_name = if ($null -ne $instance.DisplayName) { [string]$instance.DisplayName } else { $instance_id.ToString() }

                if ($instance -is [Microsoft.EnterpriseManagement.Monitoring.MonitoringObjectGroup] -or
                    $instance.GetType().Name -match 'Group' -or
                    $instance.ClassName -match 'Group') {
                    $scope_type = "Group"
                }
                else {
                    $scope_type = "Object/Instance"
                }
            }
            else {
                $target_name = $instance_id.ToString()
                $scope_type = "Object/Instance"
            }
        }
        elseif ($null -ne $override.Context) {
            # Scoped to a class (or a group class definition).
            $context_id = if ($null -ne $override.Context.Id) { $override.Context.Id } else { $override.Context }
            $context_class = Get-SCOMClass -Id $context_id -ErrorAction SilentlyContinue

            if ($null -ne $context_class) {
                $target_name = if ($null -ne $context_class.DisplayName) { [string]$context_class.DisplayName } else { $context_id.ToString() }

                if ($context_class.Name -match 'Group' -or
                    $context_class.DisplayName -match 'Group' -or
                    ($null -ne $context_class.Base -and $context_class.Base.Name -match 'Group')) {
                    $scope_type = "Group"
                }
                else {
                    $scope_type = "Class"
                }
            }
            else {
                $target_name = $context_id.ToString()
                $scope_type = "Class"
            }
        }
    }
    catch {
        $null = $_  # Scope resolution may fail for unknown override types; return defaults
    }

    return @{
        override_scope = $scope_type
        target_name = $target_name
    }
}


Function Format-MonitorResult {
    <#
    Builds the per-monitor result hashtable that includes the monitor's attributes and
    all of its overrides. If the monitor has no overrides the 'overrides' key is an
    empty array so the caller can always iterate without a null-check.
    #>
    param ([Parameter(Mandatory = $true)][object]$monitor)
    $raw_overrides = @()
    try {
        $raw_overrides = @(Get-SCOMOverride -Monitor $monitor -ErrorAction SilentlyContinue)
    }
    catch {
        $null = $_  # Get-SCOMOverride may fail for certain monitor types; treat as no overrides
    }

    $overrides = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($ov in $raw_overrides) {
        $scope_info = Get-OverrideScopeInfo -override $ov
        $ov_entry = @{
            monitor_display_name = if ($null -ne $monitor.DisplayName) { [string]$monitor.DisplayName } else { "" }
            monitor_internal_name = [string]$monitor.Name
            monitor_id = $monitor.Id.ToString()
            override_id = $ov.Id.ToString()
            override_management_pack = Get-OverrideManagementPackDisplayName -override $ov
            override_scope = $scope_info.override_scope
            target_name = $scope_info.target_name
            override_property = Get-OverridePropertyName -override $ov
            override_value = [string]$ov.Value
            enforced = [bool]$ov.Enforced
        }
        $overrides.Add($ov_entry)
    }

    return @{
        type = [string]$monitor.GetType().Name
        management_pack = Get-MonitorManagementPackDisplayName -monitor $monitor
        display_name = if ($null -ne $monitor.DisplayName) { [string]$monitor.DisplayName } else { "" }
        target_class = Get-TargetClassDisplayName -monitor $monitor
        enabled = [bool]$monitor.Enabled
        overridden = [bool]$monitor.HasNonCategoryOverride
        id = $monitor.Id.ToString()
        overrides = $overrides.ToArray()
    }
}


$spec = @{
    options = @{
        monitor_id = @{ type = "str"; required = $false; default = $null }
        monitor_display_name = @{ type = "str"; required = $false; default = $null }
        monitor_target_class = @{ type = "str"; required = $false; default = $null }
    }
    mutually_exclusive = @(
        , @("monitor_id", "monitor_display_name", "monitor_target_class")
    )
    required_one_of = @(
        , @("monitor_id", "monitor_display_name", "monitor_target_class")
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$monitor_id = $module.Params.monitor_id
$monitor_display_name = $module.Params.monitor_display_name
$monitor_target_class = $module.Params.monitor_target_class

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$monitors = @()

try {
    if ($null -ne $monitor_id) {
        $mon = Get-SCOMMonitor -Id ([System.Guid]$monitor_id) -ErrorAction SilentlyContinue
        if ($null -ne $mon) { $monitors = @($mon) }
    }
    elseif ($null -ne $monitor_display_name) {
        $monitors = @(Get-SCOMMonitor -DisplayName $monitor_display_name -ErrorAction Stop)
    }
    else {
        $class = Get-SCOMClass -DisplayName $monitor_target_class -ErrorAction SilentlyContinue
        if ($null -eq $class) {
            $module.FailJson("SCOM class with display name '$monitor_target_class' was not found.")
        }
        $monitors = @(Get-SCOMMonitor -Target $class -ErrorAction Stop)
    }
}
catch {
    $module.FailJson("Failed to retrieve SCOM monitors: $($_.Exception.Message)", $_)
}

$results = [System.Collections.Generic.List[hashtable]]::new()
foreach ($monitor in $monitors) {
    $results.Add((Format-MonitorResult -monitor $monitor))
}

$module.Result.changed = $false
$module.Result.monitors = $results.ToArray()

$module.ExitJson()
