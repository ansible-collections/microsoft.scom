#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._SCOMPsSetupUtils


$TYPE_TO_CLASS_MAP = @{
    windows = "SCOMWindowsCredentialSecureData"
    community_string = "SCOMCommunityStringSecureData"
    basic_authentication = "SCOMBasicCredentialSecureData"
    simple_authentication = "SCOMSimpleCredentialSecureData"
    digest_authentication = "SCOMDigestCredentialSecureData"
    binary_authentication = "SCOMGenericSecureData"
    action_account = "SCOMActionAccountSecureData"
}


$TYPE_TO_SWITCH_MAP = @{
    windows = "Windows"
    community_string = "CommunityString"
    basic_authentication = "Basic"
    simple_authentication = "Simple"
    digest_authentication = "Digest"
    binary_authentication = "Binary"
    action_account = "ActionAccount"
}


Function New-AddRunAsAccountArg {
    param (
        [Parameter(Mandatory = $true)][string]$AccountName,
        [Parameter(Mandatory = $true)][string]$AccountType,
        [string]$AccountDescription = $null,
        [string]$AccountUsername = $null,
        [string]$AccountPassword = $null,
        [string]$AccountDomain = $null,
        [string]$AccountCommunityString = $null,
        [string]$AccountBinaryFilePath = $null
    )

    $add_args = @{ Name = $AccountName }
    $add_args[$TYPE_TO_SWITCH_MAP[$AccountType]] = $true

    if ($null -ne $AccountDescription) {
        $add_args.Description = $AccountDescription
    }

    switch ($AccountType) {
        { $_ -in @("windows", "action_account") } {
            $secure_password = ConvertTo-SecureString -String $AccountPassword -AsPlainText -Force
            $add_args.RunAsCredential = New-Object System.Management.Automation.PSCredential(
                "$AccountDomain\$AccountUsername", $secure_password
            )
        }
        { $_ -in @("basic_authentication", "simple_authentication", "digest_authentication") } {
            $secure_password = ConvertTo-SecureString -String $AccountPassword -AsPlainText -Force
            $add_args.RunAsCredential = New-Object System.Management.Automation.PSCredential(
                $AccountUsername, $secure_password
            )
        }
        "community_string" {
            $add_args.String = ConvertTo-SecureString -String $AccountCommunityString -AsPlainText -Force
        }
        "binary_authentication" {
            $add_args.Path = $AccountBinaryFilePath
        }
    }

    return $add_args
}

Function Invoke-CreateRunAsAccount {
    param (
        [Parameter(Mandatory = $true)][string]$AccountName,
        [Parameter(Mandatory = $true)][string]$AccountType
    )

    $add_args = New-AddRunAsAccountArg `
        -AccountName $AccountName `
        -AccountType $AccountType `
        -AccountDescription $description `
        -AccountUsername $username `
        -AccountPassword $password `
        -AccountDomain $domain `
        -AccountCommunityString $community_string `
        -AccountBinaryFilePath $binary_file_path

    return (Add-SCOMRunAsAccount @add_args -ErrorAction Stop)
}

Function Invoke-UpdateRunAsAccount {
    param (
        [Parameter(Mandatory = $true)][object]$ExistingAccount,
        [Parameter(Mandatory = $true)][string]$AccountType,
        [string]$AccountUsername = $null,
        [string]$AccountPassword = $null,
        [string]$AccountDomain = $null,
        [string]$AccountCommunityString = $null,
        [string]$AccountBinaryFilePath = $null
    )

    $updated = $null

    switch ($AccountType) {
        { $_ -in @("windows", "action_account") } {
            $secure_password = ConvertTo-SecureString -String $AccountPassword -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential(
                "$AccountDomain\$AccountUsername", $secure_password
            )
            $updated = $ExistingAccount | Update-SCOMRunAsAccount -RunAsCredential $credential -PassThru -ErrorAction Stop
        }
        { $_ -in @("basic_authentication", "simple_authentication", "digest_authentication") } {
            $secure_password = ConvertTo-SecureString -String $AccountPassword -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential(
                $AccountUsername, $secure_password
            )
            $updated = $ExistingAccount | Update-SCOMRunAsAccount -RunAsCredential $credential -PassThru -ErrorAction Stop
        }
        "community_string" {
            $secure_community = ConvertTo-SecureString -String $AccountCommunityString -AsPlainText -Force
            $updated = $ExistingAccount | Update-SCOMRunAsAccount -CommunityString $secure_community -PassThru -ErrorAction Stop
        }
        "binary_authentication" {
            $updated = $ExistingAccount | Update-SCOMRunAsAccount -Path $AccountBinaryFilePath -PassThru -ErrorAction Stop
        }
    }

    if ($null -ne $updated) {
        return $updated
    }
    return $ExistingAccount
}


$spec = @{
    options = @{
        state = @{
            type = "str"
            required = $false
            default = "present"
            choices = @("present", "absent")
        }
        name = @{ type = "str"; required = $false; default = $null }
        id = @{ type = "str"; required = $false; default = $null }
        description = @{ type = "str"; required = $false; default = $null }
        account_type = @{
            type = "str"
            required = $false
            default = $null
            choices = @(
                "windows", "community_string", "basic_authentication",
                "simple_authentication", "digest_authentication",
                "binary_authentication", "action_account"
            )
        }
        update_password = @{ type = "bool"; required = $false; default = $false }
        # Windows / Action Account / Basic / Simple / Digest Authentication
        username = @{ type = "str"; required = $false; default = $null }
        password = @{ type = "str"; required = $false; default = $null; no_log = $true }
        domain = @{ type = "str"; required = $false; default = $null }
        # Community String
        community_string = @{ type = "str"; required = $false; default = $null; no_log = $true }
        # Binary Authentication
        binary_file_path = @{ type = "str"; required = $false; default = $null }
    }
    required_if = @(
        # NOTE: only entries that do NOT reference no_log parameters are safe to
        # declare here. ansible-core 2.16 Ansible.Basic throws a NullReferenceException
        # in Create() when required_if references a no_log parameter that is absent.
        # Credential-level validation is performed manually after Create() instead.
        , @("state", "absent", @("id"))
        , @("state", "present", @("name", "account_type"))
    )
    supports_check_mode = $true
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$state = $module.Params.state
$name = $module.Params.name
$id = $module.Params.id
$account_type = $module.Params.account_type
$description = $module.Params.description
$update_password = $module.Params.update_password
$username = $module.Params.username
$password = $module.Params.password
$domain = $module.Params.domain
$community_string = $module.Params.community_string
$binary_file_path = $module.Params.binary_file_path

# Credential parameter validation — equivalent to the required_if entries removed for
# ansible-core 2.16 compatibility (Ansible.Basic throws a NullReferenceException in
# Create() when required_if references a no_log parameter that is absent).
if ($null -ne $account_type) {
    $credential_errors = [System.Collections.Generic.List[string]]::new()
    switch ($account_type) {
        { $_ -in @("windows", "action_account") } {
            foreach ($p in @("username", "password", "domain")) {
                if ($null -eq $module.Params[$p]) { $credential_errors.Add($p) }
            }
        }
        { $_ -in @("basic_authentication", "simple_authentication", "digest_authentication") } {
            foreach ($p in @("username", "password")) {
                if ($null -eq $module.Params[$p]) { $credential_errors.Add($p) }
            }
        }
        "community_string" {
            if ($null -eq $community_string) { $credential_errors.Add("community_string") }
        }
        "binary_authentication" {
            if ($null -eq $binary_file_path) { $credential_errors.Add("binary_file_path") }
        }
    }
    if ($credential_errors.Count -gt 0) {
        $module.FailJson(
            "account_type '$account_type' requires the following missing parameter(s): " +
            ($credential_errors -join ", ") + "."
        )
    }
}

Import-SCOMPsModule -module $module
Connect-SCOMManagementGroup -Module $module


if ($state -eq "absent") {
    $parsed_guid = [System.Guid]::Empty
    if (-not [System.Guid]::TryParse($id, [ref]$parsed_guid)) {
        $module.FailJson("'id' is not a valid GUID: '$id'.")
    }
    $existing = $null
    try {
        $existing = Get-SCOMRunAsAccount -Id $parsed_guid -ErrorAction Stop
    }
    catch {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    if ($null -eq $existing) {
        $module.Result.changed = $false
        $module.ExitJson()
    }

    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $existing | Remove-SCOMRunAsAccount -ErrorAction Stop
        }
        catch {
            $module.FailJson("Failed to remove SCOM RunAs account (id='$id'): $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}


$type_class = $TYPE_TO_CLASS_MAP[$account_type]

$existing_accounts = @()
try {
    $candidates = Get-SCOMRunAsAccount -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $candidates) {
        $existing_accounts = @($candidates | Where-Object { $_.AccountType.ToString() -like "*$type_class*" })
    }
}
catch {
    $module.FailJson("Failed to query SCOM RunAs accounts named '$name': $($_.Exception.Message)", $_)
}

if ($existing_accounts.Count -eq 0) {
    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $new_account = Invoke-CreateRunAsAccount -AccountName $name -AccountType $account_type
        }
        catch {
            $module.FailJson("Failed to create SCOM RunAs account '$name': $($_.Exception.Message)", $_)
        }
        $module.Result.run_as_account = Format-RunAsAccountResult -account $new_account
    }
    $module.ExitJson()
}

if ($existing_accounts.Count -gt 1) {
    $duplicate_ids = ($existing_accounts | ForEach-Object { $_.Id.ToString() }) -join ", "
    $module.FailJson(
        "More than 1 '$account_type' account named '$name' exist (ids: $duplicate_ids). " +
        "Use state=absent with 'id' to remove the unwanted duplicates, then re-run."
    )
}

if (-not $update_password) {
    $module.Result.changed = $false
    $module.Result.run_as_account = Format-RunAsAccountResult -account $existing_accounts[0]
    $module.ExitJson()
}

$module.Result.changed = $true
if (-not $module.CheckMode) {
    try {
        $updated_account = Invoke-UpdateRunAsAccount `
            -ExistingAccount $existing_accounts[0] `
            -AccountType $account_type `
            -AccountUsername $username `
            -AccountPassword $password `
            -AccountDomain $domain `
            -AccountCommunityString $community_string `
            -AccountBinaryFilePath $binary_file_path
    }
    catch {
        $module.FailJson("Failed to update credentials for SCOM RunAs account '$name': $($_.Exception.Message)", $_)
    }

    $module.Result.run_as_account = Format-RunAsAccountResult -account $updated_account
}

$module.ExitJson()
