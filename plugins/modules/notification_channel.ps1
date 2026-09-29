#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils



$spec = @{
    options = @{
        display_name = @{ type = "str"; required = $true }
        description = @{ type = "str"; required = $false; default = $null }
        channel_type = @{
            type = "str"
            required = $false
            default = $null
            choices = @("smtp", "command", "sms", "im")
        }
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
        # --- SMTP (email) channel options ---
        smtp_server = @{ type = "str"; required = $false; default = $null }
        smtp_port = @{ type = "int"; required = $false; default = $null }
        return_address = @{ type = "str"; required = $false; default = $null }
        subject = @{ type = "str"; required = $false; default = $null }
        anonymous = @{ type = "bool"; required = $false; default = $false }
        body_as_html = @{ type = "bool"; required = $false; default = $false }
        backup_smtp_servers = @{ type = "list"; elements = "str"; required = $false; default = @() }
        # --- Command channel options ---
        application_path = @{ type = "str"; required = $false; default = $null }
        argument = @{ type = "str"; required = $false; default = $null }
        working_directory = @{ type = "str"; required = $false; default = $null }
        # --- IM channel options ---
        im_user = @{ type = "str"; required = $false; default = $null }
        im_server = @{ type = "str"; required = $false; default = $null }
        im_port = @{ type = "int"; required = $false; default = $null }
        im_authentication = @{
            type = "str"
            required = $false
            default = "ntlm"
            choices = @("ntlm", "kerberos")
        }
        im_protocol = @{
            type = "str"
            required = $false
            default = "tcp"
            choices = @("tcp", "tls")
        }
        # --- Shared options ---
        body = @{ type = "str"; required = $false; default = $null }
        encoding = @{ type = "str"; required = $false; default = $null }
        allow_duplicate_create = @{ type = "bool"; required = $false; default = $false }
        allow_duplicate_delete = @{ type = "bool"; required = $false; default = $false }
    }
    # ansible-core 2.16 throws a NullReferenceException when the condition key's value
    # is null (e.g. channel_type=null for state=absent), even for non-matching conditions.
    #
    # Restore channel-type entries here once ansible-core 2.16 support is dropped:
    #   , @("channel_type", "smtp", @("smtp_server", "return_address", "body"))
    #   , @("channel_type", "command", @("application_path"))
    #   , @("channel_type", "im", @("im_user", "im_server", "body"))
    #   , @("channel_type", "sms", @("body"))
    required_if = @(
        , @("state", "present", @("channel_type"))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$display_name = $module.Params.display_name
$channel_type = $module.Params.channel_type
$state = $module.Params.state
$allow_duplicate_create = $module.Params.allow_duplicate_create
$allow_duplicate_delete = $module.Params.allow_duplicate_delete

# Validate per-channel-type required parameters manually.
# (See the required_if comment in the spec for why this is done in code rather
# than via additional required_if entries.)
if ($null -ne $channel_type) {
    $missing = switch ($channel_type) {
        "smtp" {
            @("smtp_server", "return_address", "body") |
                Where-Object { $null -eq $module.Params[$_] }
        }
        "command" {
            @("application_path") |
                Where-Object { $null -eq $module.Params[$_] }
        }
        "im" {
            @("im_user", "im_server", "body") |
                Where-Object { $null -eq $module.Params[$_] }
        }
        "sms" {
            @("body") |
                Where-Object { $null -eq $module.Params[$_] }
        }
    }
    if ($missing) {
        $module.FailJson(
            "The following parameters are required when channel_type=$channel_type`: $($missing -join ', ')."
        )
    }
}

$guid = [System.Guid]::NewGuid().ToString().Replace('-', '_')
$name = switch ($channel_type) {
    "smtp" { "Smtp_$guid" }
    "im" { "Im_$guid" }
    "sms" { "Sms_$guid" }
    "command" { "Cmd_$guid" }
    default { "Scom_$guid" }
}

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module

$existing = @()
try {
    $result = Get-SCOMNotificationChannel -DisplayName $display_name -ErrorAction SilentlyContinue
    if ($null -ne $result) {
        $existing = @($result)
    }
}
catch {
    $module.FailJson("Failed to query SCOM notification channel '$display_name': $($_.Exception.Message)", $_)
}

if ($state -eq "absent") {
    if ($existing.Count -eq 0) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    if ($existing.Count -gt 1 -and -not $allow_duplicate_delete) {
        $module.FailJson(
            "$($existing.Count) channels with display name '$display_name' exist. " +
            "Set allow_duplicate_delete: true to remove all of them."
        )
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $existing | Remove-SCOMNotificationChannel -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM notification channel '$display_name': $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}

# state == present
if ($existing.Count -gt 0 -and -not $allow_duplicate_create) {
    $module.Result.changed = $false
    $module.Result.channel = Format-NotificationChannelResult -channel $existing[0]
    $module.ExitJson()
}

$module.Result.changed = $true

if (-not $module.CheckMode) {
    $add_arguments = @{
        DisplayName = $display_name
    }
    if ($null -ne $module.Params.description) {
        $add_arguments.Description = $module.Params.description
    }

    switch ($channel_type) {
        "smtp" {
            $add_arguments.Name = $name
            $add_arguments.From = $module.Params.return_address
            $add_arguments.Server = $module.Params.smtp_server
            $add_arguments.Body = $module.Params.body
            if ($null -ne $module.Params.smtp_port) { $add_arguments.Port = $module.Params.smtp_port }
            if ($null -ne $module.Params.subject) { $add_arguments.Subject = $module.Params.subject }
            if ($module.Params.anonymous) { $add_arguments.Anonymous = $true }
            if ($module.Params.body_as_html) { $add_arguments.BodyAsHtml = $true }
            if ($module.Params.backup_smtp_servers.Count -gt 0) { $add_arguments.BackupSmtpServer = $module.Params.backup_smtp_servers }
            if ($null -ne $module.Params.encoding) { $add_arguments.Encoding = $module.Params.encoding }
        }
        "command" {
            $add_arguments.Name = $name
            $add_arguments.ApplicationPath = $module.Params.application_path
            if ($null -ne $module.Params.argument) { $add_arguments.Argument = $module.Params.argument }
            if ($null -ne $module.Params.working_directory) { $add_arguments.WorkingDirectory = $module.Params.working_directory }
        }
        "im" {
            $add_arguments.Name = $name
            $add_arguments.UserName = [uri]$module.Params.im_user
            $add_arguments.Server = $module.Params.im_server
            $add_arguments.Body = $module.Params.body
            $add_arguments.SipAuthentication = $module.Params.im_authentication
            $add_arguments.SipProtocol = $module.Params.im_protocol
            if ($null -ne $module.Params.im_port) { $add_arguments.Port = $module.Params.im_port }
            if ($null -ne $module.Params.encoding) { $add_arguments.Encoding = $module.Params.encoding }
        }
        "sms" {
            $add_arguments.Name = $name
            $add_arguments.Sms = $true
            $add_arguments.Body = $module.Params.body
            if ($null -ne $module.Params.encoding) { $add_arguments.Encoding = $module.Params.encoding }
        }
    }

    try {
        Add-SCOMNotificationChannel @add_arguments -ErrorAction Stop
    }
    catch {
        $module.FailJson("Failed to create SCOM notification channel '$display_name': $($_.Exception.Message)", $_)
    }

    try {
        $refetched = Get-SCOMNotificationChannel -DisplayName $display_name -ErrorAction Stop
        if ($null -ne $refetched) {
            $existing = @($refetched)
        }
    }
    catch {
        $module.Warn("Notification channel was created but could not be re-fetched for result: $($_.Exception.Message)")
    }
}

if ($existing.Count -gt 0) {
    $module.Result.channel = Format-NotificationChannelResult -channel $existing[0]
}

$module.ExitJson()
