Set-StrictMode -Version Latest

$script:AgentGuidanceCodexPortableKeys = @(
    'model',
    'model_reasoning_effort',
    'personality',
    'service_tier',
    'suppress_unstable_features_warning',
    'approval_policy',
    'approvals_reviewer',
    'sandbox_mode',
    'memories.generate_memories',
    'memories.use_memories',
    'features.goals',
    'features.memories',
    'features.mentions_v2',
    'features.artifact',
    'features.multi_agent',
    'features.default_mode_request_user_input',
    'desktop.conversationDetailMode',
    'desktop.sansFontSize',
    'desktop.codeFontSize',
    'desktop.ambient-suggestions-enabled',
    'desktop.followUpQueueMode',
    'desktop.keepRemoteControlAwakeWhilePluggedIn',
    'tui.status_line',
    'tui.status_line_use_colors'
)
$script:AgentGuidanceCodexWindowsKeys = @('windows.sandbox')
$script:AgentGuidanceCodexRemovalKeys = @(
    'features.generate_memories',
    'features.use_memories',
    'features.js_repl',
    'features.terminal_resize_reflow',
    'tui.tui.transcript_syntax_highlight'
)
$script:AgentGuidanceKnownFiles = @(
    [pscustomobject]@{
        Name = 'Codex AGENTS.md'
        SourcePath = '~/.codex/AGENTS.md'
        DestinationPath = '.codex/AGENTS.md'
        Starter = $true
    }
    [pscustomobject]@{
        Name = 'Claude CLAUDE.md'
        SourcePath = '~/.claude/CLAUDE.md'
        DestinationPath = '.claude/CLAUDE.md'
        Starter = $true
    }
    [pscustomobject]@{
        Name = 'Grok AGENTS.md'
        SourcePath = '~/.grok/AGENTS.md'
        DestinationPath = '.grok/AGENTS.md'
        Starter = $false
    }
    [pscustomobject]@{
        Name = 'Pi AGENTS.md'
        SourcePath = '~/.pi/agent/AGENTS.md'
        DestinationPath = '.pi/agent/AGENTS.md'
        Starter = $false
    }
    [pscustomobject]@{
        Name = 'oh-my-pi AGENTS.md'
        SourcePath = '~/.omp/agent/AGENTS.md'
        DestinationPath = '.omp/agent/AGENTS.md'
        Starter = $false
    }
    [pscustomobject]@{
        Name = 'OpenCode AGENTS.md'
        SourcePath = '~/.config/opencode/AGENTS.md'
        DestinationPath = '.config/opencode/AGENTS.md'
        Starter = $false
    }
)

function Invoke-AgentGuidanceNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [string] $InputText
    )

    if ($PSBoundParameters.ContainsKey('InputText')) {
        $output = @($InputText | & $FilePath @ArgumentList 2>&1)
    }
    else {
        $output = @(& $FilePath @ArgumentList 2>&1)
    }

    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output | ForEach-Object { $_.ToString() })
    }
}

function Invoke-AgentGuidanceSsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemoteCommand,

        [string] $InputText
    )

    $arguments = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=8',
        $ComputerName,
        $RemoteCommand
    )

    if ($PSBoundParameters.ContainsKey('InputText')) {
        return Invoke-AgentGuidanceNative -FilePath 'ssh' -ArgumentList $arguments -InputText $InputText
    }

    Invoke-AgentGuidanceNative -FilePath 'ssh' -ArgumentList $arguments
}

function Invoke-AgentGuidanceWindowsPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $Script,

        [string] $InputText
    )

    $preamble = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
'@
    $encodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($preamble + [Environment]::NewLine + $Script)
    )
    $remoteCommand = 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ' + $encodedScript

    if ($PSBoundParameters.ContainsKey('InputText')) {
        return Invoke-AgentGuidanceSsh -ComputerName $ComputerName -RemoteCommand $remoteCommand -InputText $InputText
    }

    Invoke-AgentGuidanceSsh -ComputerName $ComputerName -RemoteCommand $remoteCommand
}

function Assert-AgentGuidanceSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Result,

        [Parameter(Mandatory)]
        [string] $Context
    )

    if ($Result.ExitCode -eq 0) {
        return
    }

    $detail = Get-AgentGuidanceNativeFailureDetail -Result $Result
    throw "$Context failed with exit code $($Result.ExitCode): $detail"
}

function Get-AgentGuidanceNativeFailureDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Result
    )

    $detail = (@($Result.Output) | Where-Object { $null -ne $_ } | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join '; '
    if ([string]::IsNullOrWhiteSpace($detail)) {
        return 'No command output was returned.'
    }

    $detail
}

function Test-AgentGuidanceSshUnavailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Result
    )

    if ($Result.ExitCode -ne 255) {
        return $false
    }

    $detail = Get-AgentGuidanceNativeFailureDetail -Result $Result
    $detail -match '(?i)(timed out|connection refused|no route to host|network is unreachable|host is down|could not resolve hostname|temporary failure in name resolution|name or service not known|nodename nor servname provided)'
}

function ConvertTo-AgentGuidanceShellLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $singleQuoteEscape = "'" + '"' + "'" + '"' + "'"
    "'" + $Value.Replace("'", $singleQuoteEscape) + "'"
}

function ConvertTo-AgentGuidancePowerShellLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    "'" + $Value.Replace("'", "''") + "'"
}

function Get-AgentGuidanceDefaultConfigPath {
    [CmdletBinding()]
    param()

    $configuredPath = [Environment]::GetEnvironmentVariable('AGENT_GUIDANCE_SYNC_CONFIG')
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        return $configuredPath
    }

    $profileRoot = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($profileRoot)) {
        throw 'The local user profile path is empty.'
    }

    Join-Path $profileRoot '.config/agent-guidance-sync/config.json'
}

function Get-AgentGuidanceOperatorCommand {
    [CmdletBinding()]
    param()

    $sawLongCli = $false
    foreach ($frame in Get-PSCallStack) {
        $names = [Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace([string] $frame.Command)) {
            $names.Add([string] $frame.Command)
        }
        if (-not [string]::IsNullOrWhiteSpace([string] $frame.ScriptName)) {
            $names.Add([IO.Path]::GetFileNameWithoutExtension([string] $frame.ScriptName))
        }
        foreach ($name in $names) {
            $leaf = [IO.Path]::GetFileNameWithoutExtension($name)
            if ($leaf -eq 'ag-sync') {
                return 'ag-sync'
            }
            if ($leaf -eq 'agent-guidance-sync') {
                $sawLongCli = $true
            }
        }
    }
    if ($sawLongCli) {
        return 'agent-guidance-sync'
    }
    if (Get-Command -Name ag-sync -ErrorAction SilentlyContinue) {
        return 'ag-sync'
    }
    if (Get-Command -Name agent-guidance-sync -ErrorAction SilentlyContinue) {
        return 'agent-guidance-sync'
    }

    'Sync-AgentGuidance'
}

function ConvertTo-AgentGuidanceProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $ProfileRoot
    )

    if ($Path -eq '~') {
        return [IO.Path]::GetFullPath($ProfileRoot)
    }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $relativeToProfile = $Path.Substring(2).Replace('/', [IO.Path]::DirectorySeparatorChar)
        return [IO.Path]::GetFullPath((Join-Path $ProfileRoot $relativeToProfile))
    }
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    [IO.Path]::GetFullPath((Join-Path $ProfileRoot $Path))
}

function Get-AgentGuidanceSshConfigAliases {
    [CmdletBinding()]
    param(
        [string] $SshConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($SshConfigPath)) {
        $profileRoot = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($profileRoot)) {
            return @()
        }
        $SshConfigPath = Join-Path $profileRoot '.ssh/config'
    }
    if (-not (Test-Path -LiteralPath $SshConfigPath -PathType Leaf)) {
        return @()
    }

    $aliases = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rawLine in [IO.File]::ReadAllLines($SshConfigPath)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        if ($line -notmatch '^(?i)Host\s+(.+)$') {
            continue
        }
        foreach ($token in @($Matches[1] -split '\s+' | Where-Object { $_ })) {
            if ($token -match '[*?]' -or $token.StartsWith('!')) {
                continue
            }
            if ($token -notmatch '^[A-Za-z0-9._-]+(?:@[A-Za-z0-9._-]+)?$') {
                continue
            }
            if ($seen.Add($token)) {
                $aliases.Add($token)
            }
        }
    }

    @($aliases)
}

function Select-AgentGuidanceStarterFiles {
    [CmdletBinding()]
    param(
        [string] $ProfileRoot = ([Environment]::GetFolderPath('UserProfile'))
    )

    if ([string]::IsNullOrWhiteSpace($ProfileRoot)) {
        throw 'The local user profile path is empty.'
    }

    $present = @(
        foreach ($entry in $script:AgentGuidanceKnownFiles) {
            $localPath = ConvertTo-AgentGuidanceProfilePath -Path $entry.SourcePath -ProfileRoot $ProfileRoot
            if (Test-Path -LiteralPath $localPath -PathType Leaf) {
                [pscustomobject]@{
                    Name = $entry.Name
                    SourcePath = $entry.SourcePath
                    DestinationPath = $entry.DestinationPath
                    LocalPath = $localPath
                    Present = $true
                    Fallback = $false
                }
            }
        }
    )
    if ($present.Count -gt 0) {
        return $present
    }

    @(
        foreach ($entry in $script:AgentGuidanceKnownFiles) {
            if (-not $entry.Starter) {
                continue
            }
            [pscustomobject]@{
                Name = $entry.Name
                SourcePath = $entry.SourcePath
                DestinationPath = $entry.DestinationPath
                LocalPath = (ConvertTo-AgentGuidanceProfilePath -Path $entry.SourcePath -ProfileRoot $ProfileRoot)
                Present = $false
                Fallback = $true
            }
        }
    )
}

function Initialize-AgentGuidanceConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConfigPath,

        [string] $ProfileRoot = ([Environment]::GetFolderPath('UserProfile')),

        [string] $SshConfigPath
    )

    $currentDirectory = (Get-Location).ProviderPath
    $resolvedConfigPath = Resolve-AgentGuidanceSourcePath -Path $ConfigPath -BaseDirectory $currentDirectory
    if (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf) {
        throw "A config already exists at $resolvedConfigPath. Edit that file, or pass a different -ConfigPath."
    }

    $sourceLabel = [Environment]::MachineName
    if ([string]::IsNullOrWhiteSpace($sourceLabel) -or $sourceLabel -match '[\r\n|]') {
        $sourceLabel = 'primary-workstation'
    }

    $selectedFiles = @(Select-AgentGuidanceStarterFiles -ProfileRoot $ProfileRoot)
    $document = [ordered]@{
        sourceLabel = $sourceLabel
        targets = @('host-one', 'host-two')
        files = @(
            foreach ($entry in $selectedFiles) {
                [ordered]@{
                    name = $entry.Name
                    sourcePath = $entry.SourcePath
                    destinationPath = $entry.DestinationPath
                }
            }
        )
    }
    $json = ($document | ConvertTo-Json -Depth 5) + [Environment]::NewLine

    $configDirectory = [IO.Path]::GetDirectoryName($resolvedConfigPath)
    if (-not [string]::IsNullOrWhiteSpace($configDirectory)) {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    }
    [IO.File]::WriteAllText($resolvedConfigPath, $json, [Text.UTF8Encoding]::new($false))

    $commandName = Get-AgentGuidanceOperatorCommand
    $usedFallback = @($selectedFiles | Where-Object { $_.Fallback }).Count -gt 0
    Write-Host "Wrote starter config: $resolvedConfigPath" -ForegroundColor Green
    Write-Host "Source label: $sourceLabel"
    if ($usedFallback) {
        Write-Host 'No usual guidance files were found, so the Codex + Claude starter was written.' -ForegroundColor Yellow
        Write-Host 'Preview will fail until those files exist or you edit the mappings.'
    }
    else {
        Write-Host "Included $($selectedFiles.Count) local guidance file(s):"
        foreach ($entry in $selectedFiles) {
            Write-Host "  $($entry.Name)"
            Write-Host "    $($entry.SourcePath) -> $($entry.DestinationPath)"
        }
    }

    $sshAliases = @(
        if ($PSBoundParameters.ContainsKey('SshConfigPath')) {
            Get-AgentGuidanceSshConfigAliases -SshConfigPath $SshConfigPath
        }
        else {
            Get-AgentGuidanceSshConfigAliases
        }
    )
    if ($sshAliases.Count -gt 0) {
        Write-Host "SSH aliases in ~/.ssh/config: $($sshAliases -join ', ')"
    }

    Write-Host ''
    Write-Host "Next: replace host-one and host-two with your SSH aliases, then run $commandName"
    Write-Host "Apply later with $commandName -apply"

    [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        SourceLabel = $sourceLabel
        Files = $selectedFiles
        UsedFallback = $usedFallback
        SshAliases = $sshAliases
    }
}

function Get-AgentGuidancePreviewSummary {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [pscustomobject[]] $Inventory = @()
    )

    $reachable = @($Inventory | Where-Object { $_.Availability -eq 'Reachable' })
    $skipped = @($Inventory | Where-Object { $_.Availability -eq 'Unavailable' })
    $current = 0
    $different = 0
    $missing = 0
    foreach ($target in $reachable) {
        foreach ($item in @($target.Files)) {
            switch ($item.Status) {
                'Current' { $current++ }
                'Missing' { $missing++ }
                default { $different++ }
            }
        }
    }

    [pscustomobject]@{
        ReachableCount = $reachable.Count
        SkippedCount = $skipped.Count
        SkippedNames = @($skipped.ComputerName)
        CurrentCount = $current
        DifferentCount = $different
        MissingCount = $missing
        ChangeCount = $different + $missing
        ComparedCount = $current + $different + $missing
    }
}

function ConvertTo-AgentGuidanceCountPhrase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [string] $Singular,

        [Parameter(Mandatory)]
        [string] $Plural
    )

    if ($Count -eq 1) {
        return "1 $Singular"
    }

    "$Count $Plural"
}

function Resolve-AgentGuidanceRunScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Config,

        [switch] $Settings
    )

    $commandName = Get-AgentGuidanceOperatorCommand
    $fileCount = @($Config.Files).Count
    if ($Settings) {
        if ($null -eq $Config.CodexConfig) {
            throw "No settings projection is configured. Add a codexConfig block to $($Config.ConfigPath), then rerun $commandName -settings."
        }
        return [pscustomobject]@{
            IncludeFiles = $false
            IncludeSettings = $true
        }
    }

    if ($fileCount -eq 0) {
        throw "This config only defines settings. Preview or apply them with $commandName -settings."
    }

    [pscustomobject]@{
        IncludeFiles = $true
        IncludeSettings = $false
    }
}

function Write-AgentGuidancePreviewSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Summary,

        [Parameter(Mandatory)]
        [string] $CommandName,

        [switch] $Apply,

        [switch] $Settings
    )

    $reachablePhrase = ConvertTo-AgentGuidanceCountPhrase -Count $Summary.ReachableCount -Singular 'reachable host' -Plural 'reachable hosts'
    $parts = [Collections.Generic.List[string]]::new()
    if ($Summary.CurrentCount -gt 0) {
        $parts.Add((ConvertTo-AgentGuidanceCountPhrase -Count $Summary.CurrentCount -Singular 'already matches' -Plural 'already match'))
    }
    if ($Summary.DifferentCount -gt 0) {
        $parts.Add((ConvertTo-AgentGuidanceCountPhrase -Count $Summary.DifferentCount -Singular 'will update' -Plural 'will update'))
    }
    if ($Summary.MissingCount -gt 0) {
        $parts.Add((ConvertTo-AgentGuidanceCountPhrase -Count $Summary.MissingCount -Singular 'will create' -Plural 'will create'))
    }

    $summaryLine = "Summary: $reachablePhrase"
    if ($Summary.SkippedCount -gt 0) {
        $skippedPhrase = ConvertTo-AgentGuidanceCountPhrase -Count $Summary.SkippedCount -Singular 'skipped' -Plural 'skipped'
        $summaryLine += ", $skippedPhrase ($($Summary.SkippedNames -join ', '))"
    }
    if ($parts.Count -gt 0) {
        $summaryLine += ". $($parts -join ', ')."
    }
    else {
        $summaryLine += '. No files were compared.'
    }

    Write-Host ''
    Write-Host $summaryLine -ForegroundColor Cyan

    if ($Apply) {
        return
    }

    if ($Summary.ChangeCount -eq 0) {
        Write-Host "Preview complete. Reachable hosts already match this source. No files would change." -ForegroundColor Cyan
    }
    else {
        $applyHint = if ($Settings) { "$CommandName -settings -apply" } else { "$CommandName -apply" }
        Write-Host "Preview complete. No files were changed. Run $applyHint to write this source state." -ForegroundColor Cyan
    }
}

function Resolve-AgentGuidanceSourcePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $BaseDirectory
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A source path cannot be empty.'
    }

    $profileRoot = [Environment]::GetFolderPath('UserProfile')
    if ($Path -eq '~') {
        return [IO.Path]::GetFullPath($profileRoot)
    }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $relativeToProfile = $Path.Substring(2).Replace('/', [IO.Path]::DirectorySeparatorChar)
        return [IO.Path]::GetFullPath((Join-Path $profileRoot $relativeToProfile))
    }
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    [IO.Path]::GetFullPath((Join-Path $BaseDirectory $Path))
}

function ConvertTo-AgentGuidanceRemoteRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A destination path cannot be empty.'
    }
    if ($Path -match '[\x00\r\n|]' -or $Path -match '^[A-Za-z]:' -or $Path.StartsWith('/') -or $Path.StartsWith('\')) {
        throw "Destination paths must be relative to the remote user profile: $Path"
    }

    $normalized = $Path.Replace('\', '/')
    $segments = @($normalized.Split('/'))
    if ($segments.Count -eq 0 -or $segments[0] -eq '~') {
        throw "Destination paths must be relative to the remote user profile: $Path"
    }
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..' -or $segment.Contains(':')) {
            throw "Destination paths cannot contain empty, dot, parent, or drive-qualified segments: $Path"
        }
    }

    $segments -join '/'
}

function Assert-AgentGuidanceExactCopyDestination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemoteRelativePath
    )

    $normalized = $RemoteRelativePath.Replace('\', '/').ToLowerInvariant()
    $sensitiveLeaf = '(^|/)(auth|credentials?|secrets?|tokens?|settings|config|models?)\.(json|toml|ya?ml)$'
    $statePath = '(^|/)(sessions?|state)(/|\.|$)|\.sqlite3?$|(^|/)id_(rsa|ed25519)$'
    if ($normalized -match $sensitiveLeaf -or $normalized -match $statePath) {
        if ($normalized -eq '.codex/config.toml') {
            throw 'Exact-copy mappings cannot target .codex/config.toml. Use the semantic codexConfig projection instead.'
        }
        throw "Exact-copy mappings cannot target authentication, settings, model, session, state, database, or private-key files: $RemoteRelativePath"
    }
}

function Assert-AgentGuidanceCodexKeyPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $KeyPath,

        [Parameter(Mandatory)]
        [ValidateSet('Portable', 'Windows', 'Remove')]
        [string] $Kind
    )

    if ([string]::IsNullOrWhiteSpace($KeyPath) -or $KeyPath -match '[\x00\r\n|]' -or $KeyPath -match '(^\.|\.$|\.\.)') {
        throw "Invalid Codex config key path: $KeyPath"
    }

    $allowed = switch ($Kind) {
        'Portable' { $script:AgentGuidanceCodexPortableKeys }
        'Windows' { $script:AgentGuidanceCodexWindowsKeys }
        'Remove' { $script:AgentGuidanceCodexRemovalKeys }
    }
    if ($KeyPath -cnotin $allowed) {
        throw "Codex config key '$KeyPath' is not in the safe $($Kind.ToLowerInvariant()) projection allowlist."
    }

    $KeyPath
}

function ConvertTo-AgentGuidanceCodexKeyList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory)]
        [ValidateSet('Portable', 'Windows', 'Remove')]
        [string] $Kind,

        [switch] $Required
    )

    $keys = @(
        foreach ($rawKey in @($Value)) {
            Assert-AgentGuidanceCodexKeyPath -KeyPath ([string] $rawKey) -Kind $Kind
        }
    )
    if ($Required -and $keys.Count -eq 0) {
        throw 'codexConfig.keyPaths must contain at least one safe portable setting.'
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $keys) {
        if (-not $seen.Add($key)) {
            throw "Duplicate Codex config key in $($Kind.ToLowerInvariant()) projection: $key"
        }
    }

    $keys
}

function Assert-AgentGuidanceComputerName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    if ($ComputerName -notmatch '^[A-Za-z0-9._-]+(?:@[A-Za-z0-9._-]+)?$') {
        throw "Invalid SSH target '$ComputerName'. Use a hostname, SSH alias, or user@host; put ports and identity files in SSH config."
    }

    $ComputerName
}

function Resolve-AgentGuidanceTargets {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]] $ConfiguredTarget = @(),

        [AllowEmptyCollection()]
        [string[]] $ComputerName = @(),

        [switch] $UseOverride
    )

    $selectedTargets = @(
        if ($UseOverride) {
            $ComputerName
        }
        else {
            $ConfiguredTarget
        }
    )
    if ($selectedTargets.Count -eq 0) {
        throw 'No SSH targets were selected. Add targets to the config or pass -ComputerName.'
    }

    $targetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($targetName in $selectedTargets) {
        $target = Assert-AgentGuidanceComputerName -ComputerName $targetName
        if (-not $targetSet.Add($target)) {
            throw "Duplicate SSH target selected: $target"
        }
        $target
    }
}

function Import-AgentGuidanceConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConfigPath
    )

    $currentDirectory = (Get-Location).ProviderPath
    $resolvedConfigPath = Resolve-AgentGuidanceSourcePath -Path $ConfigPath -BaseDirectory $currentDirectory
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        $commandName = Get-AgentGuidanceOperatorCommand
        throw "No config file at $resolvedConfigPath. Create a starter with $commandName -init, or pass -ConfigPath."
    }

    try {
        $config = [IO.File]::ReadAllText($resolvedConfigPath) | ConvertFrom-Json
    }
    catch {
        throw "Agent guidance config is not valid JSON: $resolvedConfigPath. $($_.Exception.Message)"
    }
    if ($null -eq $config) {
        throw "Agent guidance config is empty: $resolvedConfigPath"
    }

    $sourceLabelProperty = $config.PSObject.Properties['sourceLabel']
    $sourceLabel = if ($null -ne $sourceLabelProperty) { [string] $sourceLabelProperty.Value } else { [Environment]::MachineName }
    if ([string]::IsNullOrWhiteSpace($sourceLabel)) {
        $sourceLabel = [Environment]::MachineName
    }
    if ($sourceLabel -match '[\r\n|]') {
        throw 'sourceLabel cannot contain line breaks or pipe characters.'
    }

    $targets = @()
    $targetProperty = $config.PSObject.Properties['targets']
    if ($null -ne $targetProperty) {
        $targetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($rawTarget in @($targetProperty.Value)) {
            $target = Assert-AgentGuidanceComputerName -ComputerName ([string] $rawTarget)
            if (-not $targetSet.Add($target)) {
                throw "Duplicate SSH target in config: $target"
            }
            $targets += $target
        }
    }

    $configDirectory = [IO.Path]::GetDirectoryName($resolvedConfigPath)
    $nameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $destinationSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = @()
    $fileProperty = $config.PSObject.Properties['files']
    foreach ($rawFile in @($(if ($null -ne $fileProperty) { $fileProperty.Value }))) {
        $sourcePathProperty = $rawFile.PSObject.Properties['sourcePath']
        $destinationPathProperty = $rawFile.PSObject.Properties['destinationPath']
        if ($null -eq $sourcePathProperty -or [string]::IsNullOrWhiteSpace([string] $sourcePathProperty.Value)) {
            throw 'Every file mapping needs a non-empty sourcePath.'
        }
        if ($null -eq $destinationPathProperty -or [string]::IsNullOrWhiteSpace([string] $destinationPathProperty.Value)) {
            throw 'Every file mapping needs a non-empty destinationPath.'
        }

        $localPath = Resolve-AgentGuidanceSourcePath -Path ([string] $sourcePathProperty.Value) -BaseDirectory $configDirectory
        $remoteRelativePath = ConvertTo-AgentGuidanceRemoteRelativePath -Path ([string] $destinationPathProperty.Value)
        Assert-AgentGuidanceExactCopyDestination -RemoteRelativePath $remoteRelativePath
        $nameProperty = $rawFile.PSObject.Properties['name']
        $name = if ($null -ne $nameProperty -and -not [string]::IsNullOrWhiteSpace([string] $nameProperty.Value)) {
            [string] $nameProperty.Value
        }
        else {
            [IO.Path]::GetFileName($remoteRelativePath)
        }
        if ($name -match '[\r\n|]') {
            throw "File mapping names cannot contain line breaks or pipe characters: $name"
        }
        if (-not $nameSet.Add($name)) {
            throw "Duplicate file mapping name in config: $name"
        }
        if (-not $destinationSet.Add($remoteRelativePath)) {
            throw "Duplicate destination path in config: $remoteRelativePath"
        }

        $files += [pscustomobject]@{
            Name = $name
            LocalPath = $localPath
            RemoteRelativePath = $remoteRelativePath
        }
    }

    $codexConfig = $null
    $codexConfigProperty = $config.PSObject.Properties['codexConfig']
    if ($null -ne $codexConfigProperty -and $null -ne $codexConfigProperty.Value) {
        $rawCodexConfig = $codexConfigProperty.Value
        $sourcePathProperty = $rawCodexConfig.PSObject.Properties['sourcePath']
        $destinationPathProperty = $rawCodexConfig.PSObject.Properties['destinationPath']
        $keyPathsProperty = $rawCodexConfig.PSObject.Properties['keyPaths']
        $windowsKeyPathsProperty = $rawCodexConfig.PSObject.Properties['windowsKeyPaths']
        $removeKeyPathsProperty = $rawCodexConfig.PSObject.Properties['removeKeyPaths']

        $codexSourcePath = if ($null -ne $sourcePathProperty -and -not [string]::IsNullOrWhiteSpace([string] $sourcePathProperty.Value)) {
            Resolve-AgentGuidanceSourcePath -Path ([string] $sourcePathProperty.Value) -BaseDirectory $configDirectory
        }
        else {
            Resolve-AgentGuidanceSourcePath -Path '~/.codex/config.toml' -BaseDirectory $configDirectory
        }
        $codexDestination = if ($null -ne $destinationPathProperty -and -not [string]::IsNullOrWhiteSpace([string] $destinationPathProperty.Value)) {
            ConvertTo-AgentGuidanceRemoteRelativePath -Path ([string] $destinationPathProperty.Value)
        }
        else {
            '.codex/config.toml'
        }
        if ($codexDestination -cne '.codex/config.toml') {
            throw 'codexConfig.destinationPath must be .codex/config.toml.'
        }
        if ($null -eq $keyPathsProperty) {
            throw 'codexConfig.keyPaths is required.'
        }

        $portableKeys = @(ConvertTo-AgentGuidanceCodexKeyList -Value $keyPathsProperty.Value -Kind Portable -Required)
        $windowsKeys = @(ConvertTo-AgentGuidanceCodexKeyList -Value $(if ($null -ne $windowsKeyPathsProperty) { $windowsKeyPathsProperty.Value }) -Kind Windows)
        $removeKeys = @(ConvertTo-AgentGuidanceCodexKeyList -Value $(if ($null -ne $removeKeyPathsProperty) { $removeKeyPathsProperty.Value }) -Kind Remove)
        $allKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($key in @($portableKeys + $windowsKeys + $removeKeys)) {
            if (-not $allKeys.Add($key)) {
                throw "Codex config key appears in more than one projection list: $key"
            }
        }

        $codexConfig = [pscustomobject]@{
            Name = 'Codex config.toml settings'
            LocalPath = $codexSourcePath
            RemoteRelativePath = $codexDestination
            PortableKeys = $portableKeys
            WindowsKeys = $windowsKeys
            RemoveKeys = $removeKeys
        }
    }

    if ($files.Count -eq 0 -and $null -eq $codexConfig) {
        throw 'Agent guidance config must contain at least one file mapping or a codexConfig projection.'
    }

    [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        SourceLabel = $sourceLabel
        Targets = $targets
        Files = $files
        CodexConfig = $codexConfig
    }
}

function Resolve-AgentGuidanceTargetConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Probe
    )

    if ($Probe.ExitCode -eq 0 -and ($Probe.Output | Where-Object { $_ -eq 'AGENT_GUIDANCE_PLATFORM|Windows' })) {
        return [pscustomobject]@{
            Availability = 'Reachable'
            Platform = 'Windows'
            Failure = $null
        }
    }

    if (Test-AgentGuidanceSshUnavailable -Result $Probe) {
        return [pscustomobject]@{
            Availability = 'Unavailable'
            Platform = $null
            Failure = Get-AgentGuidanceNativeFailureDetail -Result $Probe
        }
    }

    [pscustomobject]@{
        Availability = 'Reachable'
        Platform = 'Unix'
        Failure = $null
    }
}

function Get-AgentGuidanceTargetConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    $probe = Invoke-AgentGuidanceWindowsPowerShell `
        -ComputerName $ComputerName `
        -Script "[Console]::Out.WriteLine('AGENT_GUIDANCE_PLATFORM|Windows')"
    Resolve-AgentGuidanceTargetConnection -Probe $probe
}

function Get-AgentGuidanceRemoteDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RemotePath,

        [Parameter(Mandatory)]
        [ValidateSet('Unix', 'Windows')]
        [string] $Platform
    )

    $separator = if ($Platform -eq 'Windows') { '\' } else { '/' }
    $separatorIndex = $RemotePath.LastIndexOf($separator)
    if ($separatorIndex -le 0) {
        throw "The remote path has no parent directory: $RemotePath"
    }

    $RemotePath.Substring(0, $separatorIndex)
}

function Get-AgentGuidanceRemoteHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemotePath,

        [Parameter(Mandatory)]
        [ValidateSet('Unix', 'Windows')]
        [string] $Platform
    )

    if ($Platform -eq 'Windows') {
        $pathLiteral = ConvertTo-AgentGuidancePowerShellLiteral -Value $RemotePath
        $script = @"
`$path = $pathLiteral
if ([IO.File]::Exists(`$path)) {
    `$hash = (Get-FileHash -LiteralPath `$path -Algorithm SHA256).Hash.ToLowerInvariant()
    [Console]::Out.WriteLine('AGENT_GUIDANCE_HASH|' + `$hash)
}
else {
    [Console]::Out.WriteLine('AGENT_GUIDANCE_HASH|MISSING')
}
"@
        $result = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $ComputerName -Script $script
        Assert-AgentGuidanceSuccess -Result $result -Context "Reading $ComputerName`:$RemotePath"
        $hashLine = @($result.Output | Where-Object { $_ -match '^AGENT_GUIDANCE_HASH\|' }) | Select-Object -Last 1
        if (-not $hashLine) {
            throw "Reading $ComputerName`:$RemotePath returned no hash receipt."
        }
        $hash = ($hashLine -split '\|', 2)[1]
        if ($hash -eq 'MISSING') {
            return 'MISSING'
        }
        if ($hash -notmatch '^[0-9a-f]{64}$') {
            throw "Reading $ComputerName`:$RemotePath returned an invalid hash: $hash"
        }
        return $hash
    }

    $pathLiteral = ConvertTo-AgentGuidanceShellLiteral -Value $RemotePath
    $command = 'if [ -f ' + $pathLiteral + ' ]; then sha256sum -- ' + $pathLiteral + "; else printf 'MISSING\n'; fi"
    $result = Invoke-AgentGuidanceSsh -ComputerName $ComputerName -RemoteCommand $command
    Assert-AgentGuidanceSuccess -Result $result -Context "Reading $ComputerName`:$RemotePath"

    $line = @($result.Output | Where-Object { $_.Trim() }) | Select-Object -First 1
    if (-not $line) {
        throw "Reading $ComputerName`:$RemotePath returned no hash."
    }
    if ($line.Trim() -eq 'MISSING') {
        return 'MISSING'
    }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+') {
        throw "Reading $ComputerName`:$RemotePath returned an invalid hash: $line"
    }

    $Matches[1].ToLowerInvariant()
}

function Get-AgentGuidanceWindowsContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemotePath
    )

    $pathLiteral = ConvertTo-AgentGuidancePowerShellLiteral -Value $RemotePath
    $script = @"
`$path = $pathLiteral
if (-not [IO.File]::Exists(`$path)) {
    throw 'Remote guidance file is missing: ' + `$path
}
`$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes(`$path))
[Console]::Out.WriteLine('AGENT_GUIDANCE_CONTENT|' + `$content)
"@
    $result = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $ComputerName -Script $script
    Assert-AgentGuidanceSuccess -Result $result -Context "Reading content from $ComputerName`:$RemotePath"
    $contentLine = @($result.Output | Where-Object { $_ -match '^AGENT_GUIDANCE_CONTENT\|' }) | Select-Object -Last 1
    if (-not $contentLine) {
        throw "Reading content from $ComputerName`:$RemotePath returned no receipt."
    }

    $encodedContent = ($contentLine -split '\|', 2)[1]
    [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($encodedContent))
}

function Get-AgentGuidanceRemoteContentBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $RemotePath,

        [Parameter(Mandatory)]
        [ValidateSet('Unix', 'Windows')]
        [string] $Platform
    )

    if ($Platform -eq 'Windows') {
        $pathLiteral = ConvertTo-AgentGuidancePowerShellLiteral -Value $RemotePath
        $script = @"
`$path = $pathLiteral
if (-not [IO.File]::Exists(`$path)) {
    throw 'Remote file is missing: ' + `$path
}
`$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes(`$path))
[Console]::Out.WriteLine('AGENT_GUIDANCE_CONTENT|' + `$content)
"@
        $result = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $ComputerName -Script $script
    }
    else {
        $pathLiteral = ConvertTo-AgentGuidanceShellLiteral -Value $RemotePath
        $command = 'set -eu; test -f ' + $pathLiteral + "; printf 'AGENT_GUIDANCE_CONTENT|'; base64 < " + $pathLiteral + " | tr -d '\r\n'; printf '\n'"
        $result = Invoke-AgentGuidanceSsh -ComputerName $ComputerName -RemoteCommand $command
    }

    Assert-AgentGuidanceSuccess -Result $result -Context "Reading content from $ComputerName`:$RemotePath"
    $contentLine = @($result.Output | Where-Object { $_ -match '^AGENT_GUIDANCE_CONTENT\|' }) | Select-Object -Last 1
    if (-not $contentLine) {
        throw "Reading content from $ComputerName`:$RemotePath returned no receipt."
    }

    try {
        ,([Convert]::FromBase64String(($contentLine -split '\|', 2)[1]))
    }
    catch {
        throw "Reading content from $ComputerName`:$RemotePath returned invalid base64."
    }
}

function New-AgentGuidanceTemporaryCodexHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]] $ConfigBytes
    )

    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $codexHome = Join-Path $temporaryRoot ('agent-guidance-sync-codex-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($codexHome)
    [IO.File]::WriteAllBytes((Join-Path $codexHome 'config.toml'), $ConfigBytes)
    $codexHome
}

function Remove-AgentGuidanceTemporaryCodexHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $leaf = [IO.Path]::GetFileName($resolvedPath)
    if (-not $resolvedPath.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $leaf.StartsWith('agent-guidance-sync-codex-', [StringComparison]::Ordinal)) {
        throw "Refusing to remove an unexpected temporary Codex home: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath) {
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            try {
                Remove-Item -LiteralPath $resolvedPath -Recurse -Force -ErrorAction Stop
                return
            }
            catch {
                if ($attempt -ge 20) {
                    throw
                }
                Start-Sleep -Milliseconds 100
            }
        }
    }
}

function Read-AgentGuidanceCodexResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [long] $Id,

        [int] $TimeoutSeconds = 30
    )

    while ($true) {
        $readTask = $Process.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "Codex app-server timed out waiting for response $Id."
        }
        $line = $readTask.Result
        if ($null -eq $line) {
            throw "Codex app-server exited before returning response $Id."
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $message = $line | ConvertFrom-Json
        }
        catch {
            throw 'Codex app-server returned a non-JSON response.'
        }
        $idProperty = $message.PSObject.Properties['id']
        if ($null -eq $idProperty -or [long] $idProperty.Value -ne $Id) {
            continue
        }
        $errorProperty = $message.PSObject.Properties['error']
        if ($null -ne $errorProperty -and $null -ne $errorProperty.Value) {
            $errorMessageProperty = $errorProperty.Value.PSObject.Properties['message']
            $errorMessage = if ($null -ne $errorMessageProperty) { [string] $errorMessageProperty.Value } else { 'unknown app-server error' }
            throw "Codex app-server request failed: $errorMessage"
        }
        $resultProperty = $message.PSObject.Properties['result']
        if ($null -eq $resultProperty) {
            throw "Codex app-server response $Id contained no result."
        }
        return $resultProperty.Value
    }
}

function Invoke-AgentGuidanceCodexAppServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CodexHome,

        [Parameter(Mandatory)]
        [pscustomobject[]] $Request
    )

    $codexCommand = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $codexCommand) {
        throw 'Codex CLI is required for semantic config.toml projection but is not available on PATH.'
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $codexCommand.Source
    [void]$startInfo.ArgumentList.Add('app-server')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $CodexHome
    $startInfo.Environment['CODEX_HOME'] = $CodexHome

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stderrTask = $null
    $started = $false
    try {
        if (-not $process.Start()) {
            throw 'Codex app-server did not start.'
        }
        $started = $true
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $initialize = [ordered]@{
            id = 1
            method = 'initialize'
            params = [ordered]@{
                clientInfo = [ordered]@{
                    name = 'agent-guidance-sync'
                    version = '0.3.0'
                }
            }
        } | ConvertTo-Json -Compress -Depth 20
        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.Flush()
        $null = Read-AgentGuidanceCodexResponse -Process $process -Id 1
        $process.StandardInput.WriteLine((@{ method = 'initialized'; params = @{} } | ConvertTo-Json -Compress))
        $process.StandardInput.Flush()

        $results = @()
        $requestId = 100L
        foreach ($item in $Request) {
            $payload = [ordered]@{
                id = $requestId
                method = $item.Method
                params = $item.Params
            } | ConvertTo-Json -Compress -Depth 100
            $process.StandardInput.WriteLine($payload)
            $process.StandardInput.Flush()
            $results += Read-AgentGuidanceCodexResponse -Process $process -Id $requestId
            $requestId++
        }
        $results
    }
    catch {
        $baseMessage = $_.Exception.Message
        if ($started -and $process.HasExited -and $null -ne $stderrTask -and $stderrTask.IsCompleted) {
            $stderr = $stderrTask.Result.Trim()
            if ($stderr) {
                $baseMessage += ' ' + $stderr.Substring(0, [Math]::Min(1000, $stderr.Length))
            }
        }
        throw $baseMessage
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(2000)) {
                $process.Kill($true)
                $process.WaitForExit()
            }
        }
        $process.Dispose()
    }
}

function Get-AgentGuidanceCodexSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CodexHome
    )

    $responses = @(Invoke-AgentGuidanceCodexAppServer -CodexHome $CodexHome -Request @(
        [pscustomobject]@{
            Method = 'config/read'
            Params = [ordered]@{ includeLayers = $true }
        }
    ))
    $response = $responses[0]
    $userLayer = @($response.layers | Where-Object {
        $name = $_.name
        $name.PSObject.Properties['type'] -and $name.type -eq 'user' -and (-not $name.PSObject.Properties['profile'] -or $null -eq $name.profile)
    }) | Select-Object -First 1
    if ($null -eq $userLayer) {
        throw 'Codex app-server returned no writable user config layer.'
    }

    [pscustomobject]@{
        Config = ConvertFrom-AgentGuidanceCodexValue -Value $userLayer.config
        Version = [string] $userLayer.version
    }
}

function ConvertFrom-AgentGuidanceCodexValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [Collections.IDictionary]) {
        $converted = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $converted[[string] $key] = ConvertFrom-AgentGuidanceCodexValue -Value $Value[$key]
        }
        return [pscustomobject] $converted
    }
    if ($Value -is [Collections.IEnumerable]) {
        return ,@($Value | ForEach-Object { ConvertFrom-AgentGuidanceCodexValue -Value $_ })
    }

    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -eq 1 -and $properties[0].Name -ceq '$serde_json::private::Number') {
        $numberText = [string] $properties[0].Value
        $integerValue = 0L
        if ([long]::TryParse($numberText, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref] $integerValue)) {
            return $integerValue
        }
        $floatingValue = 0.0
        if ([double]::TryParse($numberText, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref] $floatingValue)) {
            return $floatingValue
        }
        throw "Codex app-server returned an invalid TOML number wrapper: $numberText"
    }

    $converted = [ordered]@{}
    foreach ($property in $properties) {
        $converted[$property.Name] = ConvertFrom-AgentGuidanceCodexValue -Value $property.Value
    }
    [pscustomobject] $converted
}

function Get-AgentGuidanceObjectPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [string] $KeyPath
    )

    $value = $InputObject
    foreach ($segment in $KeyPath.Split('.')) {
        if ($null -eq $value) {
            return [pscustomobject]@{ Exists = $false; Value = $null }
        }
        if ($value -is [Collections.IDictionary]) {
            if (-not $value.Contains($segment)) {
                return [pscustomobject]@{ Exists = $false; Value = $null }
            }
            $value = $value[$segment]
            continue
        }
        $property = $value.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return [pscustomobject]@{ Exists = $false; Value = $null }
        }
        $value = $property.Value
    }

    [pscustomobject]@{ Exists = $true; Value = $value }
}

function ConvertTo-AgentGuidanceConfigDisplayValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return 'null'
    }
    $Value | ConvertTo-Json -Compress -Depth 20
}

function Test-AgentGuidanceConfigValueEqual {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $First,

        [AllowNull()]
        $Second
    )

    (ConvertTo-AgentGuidanceConfigDisplayValue -Value $First) -ceq (ConvertTo-AgentGuidanceConfigDisplayValue -Value $Second)
}

function Get-AgentGuidanceCodexSourceSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Required Codex source config is missing: $ConfigPath"
    }
    $codexHome = New-AgentGuidanceTemporaryCodexHome -ConfigBytes ([IO.File]::ReadAllBytes($ConfigPath))
    try {
        Get-AgentGuidanceCodexSnapshot -CodexHome $codexHome
    }
    finally {
        Remove-AgentGuidanceTemporaryCodexHome -Path $codexHome
    }
}

function New-AgentGuidanceCodexCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]] $TargetConfigBytes,

        [Parameter(Mandatory)]
        [pscustomobject] $SourceSnapshot,

        [Parameter(Mandatory)]
        [pscustomobject] $CodexConfig,

        [Parameter(Mandatory)]
        [ValidateSet('Unix', 'Windows')]
        [string] $Platform
    )

    $codexHome = New-AgentGuidanceTemporaryCodexHome -ConfigBytes $TargetConfigBytes
    try {
        $targetSnapshot = Get-AgentGuidanceCodexSnapshot -CodexHome $codexHome
        $edits = @()
        $changes = @()
        $setKeys = @($CodexConfig.PortableKeys)
        if ($Platform -eq 'Windows') {
            $setKeys += @($CodexConfig.WindowsKeys)
        }

        foreach ($key in $setKeys) {
            $sourceValue = Get-AgentGuidanceObjectPath -InputObject $SourceSnapshot.Config -KeyPath $key
            if (-not $sourceValue.Exists) {
                throw "The source Codex config does not define required projected key '$key'."
            }
            $targetValue = Get-AgentGuidanceObjectPath -InputObject $targetSnapshot.Config -KeyPath $key
            if ($targetValue.Exists -and (Test-AgentGuidanceConfigValueEqual -First $targetValue.Value -Second $sourceValue.Value)) {
                continue
            }

            $edits += [ordered]@{ keyPath = $key; value = $sourceValue.Value; mergeStrategy = 'replace' }
            $changes += [pscustomobject]@{
                Action = 'Set'
                KeyPath = $key
                Current = if ($targetValue.Exists) { ConvertTo-AgentGuidanceConfigDisplayValue -Value $targetValue.Value } else { '<absent>' }
                Desired = ConvertTo-AgentGuidanceConfigDisplayValue -Value $sourceValue.Value
            }
        }
        foreach ($key in $CodexConfig.RemoveKeys) {
            $targetValue = Get-AgentGuidanceObjectPath -InputObject $targetSnapshot.Config -KeyPath $key
            if (-not $targetValue.Exists) {
                continue
            }
            $edits += [ordered]@{ keyPath = $key; value = $null; mergeStrategy = 'replace' }
            $changes += [pscustomobject]@{
                Action = 'Remove'
                KeyPath = $key
                Current = ConvertTo-AgentGuidanceConfigDisplayValue -Value $targetValue.Value
                Desired = '<removed>'
            }
        }

        if ($edits.Count -gt 0) {
            $null = @(Invoke-AgentGuidanceCodexAppServer -CodexHome $codexHome -Request @(
                [pscustomobject]@{
                    Method = 'config/batchWrite'
                    Params = [ordered]@{
                        edits = $edits
                        expectedVersion = $targetSnapshot.Version
                        reloadUserConfig = $false
                    }
                }
            ))
            $null = Get-AgentGuidanceCodexSnapshot -CodexHome $codexHome
        }

        $candidatePath = Join-Path $codexHome 'config.toml'
        [pscustomobject]@{
            LocalPath = $candidatePath
            LocalHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
            Changes = $changes
            TemporaryDirectory = $codexHome
        }
    }
    catch {
        Remove-AgentGuidanceTemporaryCodexHome -Path $codexHome
        throw
    }
}

function Set-AgentGuidanceWindowsStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [string] $StagePath,

        [Parameter(Mandatory)]
        [string] $LocalPath
    )

    $stageLiteral = ConvertTo-AgentGuidancePowerShellLiteral -Value $StagePath
    $script = @"
`$stage = $stageLiteral
`$directory = [IO.Path]::GetDirectoryName(`$stage)
[void][IO.Directory]::CreateDirectory(`$directory)
`$payload = [Console]::In.ReadToEnd().Trim()
[IO.File]::WriteAllBytes(`$stage, [Convert]::FromBase64String(`$payload))
[Console]::Out.WriteLine('AGENT_GUIDANCE_STAGED|' + `$stage)
"@
    $payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($LocalPath))
    $result = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $ComputerName -Script $script -InputText $payload
    Assert-AgentGuidanceSuccess -Result $result -Context "Staging $LocalPath on $ComputerName"
    if (-not ($result.Output | Where-Object { $_ -eq "AGENT_GUIDANCE_STAGED|$StagePath" })) {
        throw "Staging $LocalPath on $ComputerName returned no receipt."
    }
}

function Get-AgentGuidanceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ComputerName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]] $File
    )

    $inventory = @()
    foreach ($computer in $ComputerName) {
        Write-Host "Checking $computer..." -ForegroundColor Cyan

        $connection = Get-AgentGuidanceTargetConnection -ComputerName $computer
        if ($connection.Availability -eq 'Unavailable') {
            $inventory += [pscustomobject]@{
                ComputerName = $computer
                Availability = 'Unavailable'
                Failure = $connection.Failure
                RemoteHome = $null
                Platform = $null
                Files = @()
            }
            continue
        }

        $platform = $connection.Platform
        if ($platform -eq 'Windows') {
            $preflightScript = @'
$homePath = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($homePath)) {
    throw 'The Windows user profile path is empty.'
}
[Console]::Out.WriteLine('AGENT_GUIDANCE_HOME|' + $homePath)
'@
            $preflight = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $computer -Script $preflightScript
            Assert-AgentGuidanceSuccess -Result $preflight -Context "Windows SSH preflight for $computer"
            $homeLine = @($preflight.Output | Where-Object { $_ -match '^AGENT_GUIDANCE_HOME\|' }) | Select-Object -Last 1
            if (-not $homeLine) {
                throw "Resolving the Windows user profile on $computer returned no receipt."
            }
            $remoteHome = ($homeLine -split '\|', 2)[1]
            if ($remoteHome -notmatch '^[A-Za-z]:\\') {
                throw "The remote home directory from $computer is not a safe Windows path: $remoteHome"
            }
        }
        else {
            $preflightCommand = 'set -eu; for command_name in sha256sum diff cp mv mkdir chmod rm base64 tr; do command -v "$command_name" >/dev/null; done; printf "ok\n"'
            $preflight = Invoke-AgentGuidanceSsh -ComputerName $computer -RemoteCommand $preflightCommand
            Assert-AgentGuidanceSuccess -Result $preflight -Context "Unix SSH preflight for $computer"

            $homeResult = Invoke-AgentGuidanceSsh -ComputerName $computer -RemoteCommand 'printf "%s\n" "$HOME"'
            Assert-AgentGuidanceSuccess -Result $homeResult -Context "Resolving the home directory on $computer"
            $remoteHome = (@($homeResult.Output | Where-Object { $_.Trim() }) | Select-Object -First 1).Trim()
            if ($remoteHome -notmatch '^/[A-Za-z0-9._/-]+$') {
                throw "The remote home directory from $computer is not a safe Unix path: $remoteHome"
            }
        }

        $remoteFiles = @()
        foreach ($item in $File) {
            $remotePath = if ($platform -eq 'Windows') {
                $remoteHome.TrimEnd('\') + '\' + $item.RemoteRelativePath.Replace('/', '\')
            }
            else {
                $remoteHome.TrimEnd('/') + '/' + $item.RemoteRelativePath
            }
            $remoteHash = Get-AgentGuidanceRemoteHash -ComputerName $computer -RemotePath $remotePath -Platform $platform
            $status = if ($remoteHash -eq $item.LocalHash) { 'Current' } elseif ($remoteHash -eq 'MISSING') { 'Missing' } else { 'Different' }

            $remoteFiles += [pscustomobject]@{
                Name = $item.Name
                Kind = 'ExactFile'
                LocalPath = $item.LocalPath
                LocalHash = $item.LocalHash
                RemoteRelativePath = $item.RemoteRelativePath
                RemotePath = $remotePath
                RemoteHash = $remoteHash
                Status = $status
                Platform = $platform
                NewFileMode = '644'
                Changes = @()
                TemporaryDirectory = $null
            }
        }

        $inventory += [pscustomobject]@{
            ComputerName = $computer
            Availability = 'Reachable'
            Failure = $null
            RemoteHome = $remoteHome
            Platform = $platform
            Files = $remoteFiles
        }
    }

    $inventory
}

function Add-AgentGuidanceCodexConfigInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]] $Inventory,

        [Parameter(Mandatory)]
        [pscustomobject] $CodexConfig,

        [Parameter(Mandatory)]
        [pscustomobject] $SourceSnapshot
    )

    $createdHomes = @()
    try {
        foreach ($target in $Inventory) {
            if ($target.PSObject.Properties['Availability'] -and $target.Availability -eq 'Unavailable') {
                continue
            }

            $remotePath = if ($target.Platform -eq 'Windows') {
                $target.RemoteHome.TrimEnd('\') + '\' + $CodexConfig.RemoteRelativePath.Replace('/', '\')
            }
            else {
                $target.RemoteHome.TrimEnd('/') + '/' + $CodexConfig.RemoteRelativePath
            }
            $remoteHash = Get-AgentGuidanceRemoteHash `
                -ComputerName $target.ComputerName `
                -RemotePath $remotePath `
                -Platform $target.Platform
            $remoteBytes = if ($remoteHash -eq 'MISSING') {
                ,([byte[]]::new(0))
            }
            else {
                Get-AgentGuidanceRemoteContentBytes `
                    -ComputerName $target.ComputerName `
                    -RemotePath $remotePath `
                    -Platform $target.Platform
            }
            if ($remoteHash -ne 'MISSING') {
                $downloadedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($remoteBytes)).ToLowerInvariant()
                if ($downloadedHash -ne $remoteHash) {
                    throw "Codex config changed while it was being read from $($target.ComputerName); rerun the preview."
                }
            }

            $candidate = New-AgentGuidanceCodexCandidate `
                -TargetConfigBytes $remoteBytes `
                -SourceSnapshot $SourceSnapshot `
                -CodexConfig $CodexConfig `
                -Platform $target.Platform
            $createdHomes += $candidate.TemporaryDirectory
            $status = if ($remoteHash -eq $candidate.LocalHash) { 'Current' } elseif ($remoteHash -eq 'MISSING') { 'Missing' } else { 'Different' }
            $target.Files = @($target.Files) + [pscustomobject]@{
                Name = $CodexConfig.Name
                Kind = 'CodexConfig'
                LocalPath = $candidate.LocalPath
                LocalHash = $candidate.LocalHash
                RemoteRelativePath = $CodexConfig.RemoteRelativePath
                RemotePath = $remotePath
                RemoteHash = $remoteHash
                Status = $status
                Platform = $target.Platform
                NewFileMode = '600'
                Changes = @($candidate.Changes)
                TemporaryDirectory = $candidate.TemporaryDirectory
            }
        }
    }
    catch {
        foreach ($codexHome in $createdHomes) {
            if (Test-Path -LiteralPath $codexHome) {
                Remove-AgentGuidanceTemporaryCodexHome -Path $codexHome
            }
        }
        throw
    }

    $Inventory
}

function Remove-AgentGuidanceInventoryTemporaryFiles {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [pscustomobject[]] $Inventory = @()
    )

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($target in $Inventory) {
        foreach ($item in $target.Files) {
            $temporaryProperty = $item.PSObject.Properties['TemporaryDirectory']
            if ($null -eq $temporaryProperty -or [string]::IsNullOrWhiteSpace([string] $temporaryProperty.Value)) {
                continue
            }
            $temporaryDirectory = [string] $temporaryProperty.Value
            if ($seen.Add($temporaryDirectory) -and (Test-Path -LiteralPath $temporaryDirectory)) {
                Remove-AgentGuidanceTemporaryCodexHome -Path $temporaryDirectory
            }
        }
    }
}

function Show-AgentGuidancePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]] $Inventory,

        [Parameter(Mandatory)]
        [string] $SourceLabel
    )

    foreach ($target in $Inventory) {
        Write-Host ''
        Write-Host $target.ComputerName -ForegroundColor Yellow

        if ($target.PSObject.Properties['Availability'] -and $target.Availability -eq 'Unavailable') {
            Write-Host "  unavailable; skipped: $($target.Failure)" -ForegroundColor DarkYellow
            continue
        }

        foreach ($item in $target.Files) {
            $kind = if ($item.PSObject.Properties['Kind']) { [string] $item.Kind } else { 'ExactFile' }
            if ($item.Status -eq 'Current') {
                Write-Host "  $($item.Name): already matches" -ForegroundColor Green
                continue
            }

            if ($kind -eq 'CodexConfig') {
                $state = if ($item.Status -eq 'Missing') { 'will create' } else { 'settings will change' }
                Write-Host "  $($item.Name): $state" -ForegroundColor Magenta
                foreach ($change in $item.Changes) {
                    if ($change.Action -eq 'Remove') {
                        Write-Host "    - $($change.KeyPath) (currently $($change.Current))"
                    }
                    else {
                        Write-Host "    ~ $($change.KeyPath): $($change.Current) -> $($change.Desired)"
                    }
                }
                continue
            }

            if ($item.Status -eq 'Missing') {
                Write-Host "  $($item.Name): will create" -ForegroundColor Magenta
                continue
            }

            Write-Host "  $($item.Name): will update" -ForegroundColor Magenta
            if ($target.Platform -eq 'Windows') {
                $remoteText = Get-AgentGuidanceWindowsContent `
                    -ComputerName $target.ComputerName `
                    -RemotePath $item.RemotePath
                $remoteText = $remoteText.Replace("`r`n", "`n").Replace("`r", "`n")
                $remoteText = $remoteText.TrimEnd([char[]]"`r`n") + "`n"
                $diffArguments = @(
                    '-c', 'core.autocrlf=false',
                    '-c', 'core.safecrlf=false',
                    'diff', '--no-index', '--text', '--no-ext-diff', '--ignore-space-at-eol', '--unified=3',
                    '--', $item.LocalPath, '-'
                )
                $diff = Invoke-AgentGuidanceNative -FilePath 'git' -ArgumentList $diffArguments -InputText $remoteText
                if ($diff.ExitCode -gt 1) {
                    Assert-AgentGuidanceSuccess -Result $diff -Context "Diffing $($item.Name) on $($target.ComputerName)"
                }
                if ($diff.ExitCode -eq 0) {
                    Write-Host '    Byte-level difference only; normalized text is identical.'
                    continue
                }
                foreach ($line in $diff.Output) {
                    if ($line -match '^(diff --git|index )') {
                        continue
                    }
                    if ($line -match '^--- ') {
                        Write-Host "    --- $SourceLabel/$($item.Name)"
                        continue
                    }
                    if ($line -match '^\+\+\+ ') {
                        Write-Host "    +++ $($target.ComputerName)/$($item.Name)"
                        continue
                    }
                    Write-Host "    $line"
                }
                continue
            }

            $remotePathLiteral = ConvertTo-AgentGuidanceShellLiteral -Value $item.RemotePath
            $localLabel = ConvertTo-AgentGuidanceShellLiteral -Value "$SourceLabel/$($item.Name)"
            $remoteLabel = ConvertTo-AgentGuidanceShellLiteral -Value "$($target.ComputerName)/$($item.Name)"
            $diffCommand = 'diff --strip-trailing-cr -u --label ' + $localLabel + ' --label ' + $remoteLabel + ' - ' + $remotePathLiteral + '; status=$?; if [ "$status" -gt 1 ]; then exit "$status"; fi'
            $localText = [System.IO.File]::ReadAllText($item.LocalPath)
            $diff = Invoke-AgentGuidanceSsh -ComputerName $target.ComputerName -RemoteCommand $diffCommand -InputText $localText
            Assert-AgentGuidanceSuccess -Result $diff -Context "Diffing $($item.Name) on $($target.ComputerName)"
            foreach ($line in $diff.Output) {
                Write-Host "    $line"
            }
        }
    }
}

function New-AgentGuidanceCommitCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DestinationPath,

        [Parameter(Mandatory)]
        [string] $StagePath,

        [Parameter(Mandatory)]
        [string] $ExpectedHash,

        [Parameter(Mandatory)]
        [string] $WantedHash,

        [Parameter(Mandatory)]
        [string] $BackupSuffix,

        [Parameter(Mandatory)]
        [string] $DisplayName,

        [ValidateSet('600', '644')]
        [string] $NewFileMode = '644'
    )

    $template = @'
set -eu
destination=__DESTINATION__
stage=__STAGE__
expected=__EXPECTED__
wanted=__WANTED__
backup_suffix=__BACKUP_SUFFIX__
display_name=__DISPLAY_NAME__
new_file_mode=__NEW_FILE_MODE__

current=MISSING
if [ -f "$destination" ]; then
    checksum_line=$(sha256sum -- "$destination")
    current=${checksum_line%% *}
fi

if [ "$current" != "$expected" ]; then
    printf 'REMOTE_CHANGED|%s|expected=%s|actual=%s\n' "$display_name" "$expected" "$current" >&2
    exit 42
fi

stage_line=$(sha256sum -- "$stage")
stage_hash=${stage_line%% *}
if [ "$stage_hash" != "$wanted" ]; then
    printf 'STAGE_HASH_MISMATCH|%s|expected=%s|actual=%s\n' "$display_name" "$wanted" "$stage_hash" >&2
    exit 43
fi

if [ "$current" = "$wanted" ]; then
    rm -f -- "$stage"
    printf 'UNCHANGED|%s|%s|%s\n' "$display_name" "$destination" "$wanted"
    exit 0
fi

backup=NONE
if [ -f "$destination" ]; then
    backup="${destination}.bak.${backup_suffix}"
    if [ -e "$backup" ]; then
        printf 'BACKUP_EXISTS|%s|%s\n' "$display_name" "$backup" >&2
        exit 44
    fi
    cp -p -- "$destination" "$backup"
    chmod --reference="$destination" "$stage"
else
    chmod "$new_file_mode" "$stage"
fi

mv -- "$stage" "$destination"
actual_line=$(sha256sum -- "$destination")
actual=${actual_line%% *}
if [ "$actual" != "$wanted" ]; then
    if [ "$backup" != NONE ]; then
        cp -p -- "$backup" "$destination"
    else
        rm -f -- "$destination"
    fi
    printf 'READBACK_HASH_MISMATCH|%s|expected=%s|actual=%s\n' "$display_name" "$wanted" "$actual" >&2
    exit 45
fi

printf 'UPDATED|%s|%s|%s|%s\n' "$display_name" "$destination" "$backup" "$actual"
'@

    $template.Replace('__DESTINATION__', (ConvertTo-AgentGuidanceShellLiteral -Value $DestinationPath)).
        Replace('__STAGE__', (ConvertTo-AgentGuidanceShellLiteral -Value $StagePath)).
        Replace('__EXPECTED__', (ConvertTo-AgentGuidanceShellLiteral -Value $ExpectedHash)).
        Replace('__WANTED__', (ConvertTo-AgentGuidanceShellLiteral -Value $WantedHash)).
        Replace('__BACKUP_SUFFIX__', (ConvertTo-AgentGuidanceShellLiteral -Value $BackupSuffix)).
        Replace('__DISPLAY_NAME__', (ConvertTo-AgentGuidanceShellLiteral -Value $DisplayName)).
        Replace('__NEW_FILE_MODE__', (ConvertTo-AgentGuidanceShellLiteral -Value $NewFileMode))
}

function New-AgentGuidanceWindowsCommitScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DestinationPath,

        [Parameter(Mandatory)]
        [string] $StagePath,

        [Parameter(Mandatory)]
        [string] $ExpectedHash,

        [Parameter(Mandatory)]
        [string] $WantedHash,

        [Parameter(Mandatory)]
        [string] $BackupSuffix,

        [Parameter(Mandatory)]
        [string] $DisplayName
    )

    $template = @'
$destination = __DESTINATION__
$stage = __STAGE__
$expected = __EXPECTED__
$wanted = __WANTED__
$backupSuffix = __BACKUP_SUFFIX__
$displayName = __DISPLAY_NAME__

function Get-ExactHash([string] $Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$current = if ([IO.File]::Exists($destination)) { Get-ExactHash $destination } else { 'MISSING' }
if ($current -ne $expected) {
    throw "REMOTE_CHANGED|$displayName|expected=$expected|actual=$current"
}

$stageHash = Get-ExactHash $stage
if ($stageHash -ne $wanted) {
    throw "STAGE_HASH_MISMATCH|$displayName|expected=$wanted|actual=$stageHash"
}

if ($current -eq $wanted) {
    [IO.File]::Delete($stage)
    [Console]::Out.WriteLine("UNCHANGED|$displayName|$destination|$wanted")
    return
}

$backup = 'NONE'
if ([IO.File]::Exists($destination)) {
    $backup = $destination + '.bak.' + $backupSuffix
    if ([IO.File]::Exists($backup)) {
        throw "BACKUP_EXISTS|$displayName|$backup"
    }
    [IO.File]::Replace($stage, $destination, $backup, $true)
}
else {
    [IO.File]::Move($stage, $destination)
}

$actual = Get-ExactHash $destination
if ($actual -ne $wanted) {
    if ($backup -ne 'NONE') {
        [IO.File]::Copy($backup, $destination, $true)
    }
    else {
        [IO.File]::Delete($destination)
    }
    throw "READBACK_HASH_MISMATCH|$displayName|expected=$wanted|actual=$actual"
}

[Console]::Out.WriteLine("UPDATED|$displayName|$destination|$backup|$actual")
'@

    $template.Replace('__DESTINATION__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $DestinationPath)).
        Replace('__STAGE__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $StagePath)).
        Replace('__EXPECTED__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $ExpectedHash)).
        Replace('__WANTED__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $WantedHash)).
        Replace('__BACKUP_SUFFIX__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $BackupSuffix)).
        Replace('__DISPLAY_NAME__', (ConvertTo-AgentGuidancePowerShellLiteral -Value $DisplayName))
}

function Sync-AgentGuidance {
    <#
    .SYNOPSIS
    Previews or applies local agent guidance and selected Codex settings over SSH.

    .DESCRIPTION
    Reads source files, an optional allowlisted Codex config projection, target
    SSH aliases, and home-relative destination paths from a JSON config. Without
    -apply, shows differences and makes no changes. Default preview and -apply
    write instruction files only. -settings previews or applies the configured
    Codex settings projection and does not copy instruction files. With -apply,
    stages every selected payload first, fences against concurrent remote edits,
    creates timestamped backups, replaces each file atomically, and verifies
    SHA-256 readback. Targets with a hard SSH reachability failure during the
    initial probe are reported and skipped. Authentication, host-key, preflight,
    staging, commit, and verification failures still stop the run. -init writes
    a local starter config and does not connect to any host.

    .EXAMPLE
    ag-sync -init

    .EXAMPLE
    ag-sync

    .EXAMPLE
    ag-sync -apply

    .EXAMPLE
    ag-sync -settings

    .EXAMPLE
    ag-sync -settings -apply

    .EXAMPLE
    ag-sync -ComputerName host-one -apply
    #>
    [CmdletBinding(DefaultParameterSetName = 'Sync')]
    [Alias('ag-sync')]
    param(
        [Parameter(ParameterSetName = 'Sync')]
        [ValidatePattern('^[A-Za-z0-9._-]+(?:@[A-Za-z0-9._-]+)?$')]
        [string[]] $ComputerName,

        [Parameter(ParameterSetName = 'Sync')]
        [Parameter(ParameterSetName = 'Init')]
        [string] $ConfigPath = (Get-AgentGuidanceDefaultConfigPath),

        [Parameter(ParameterSetName = 'Sync')]
        [switch] $Apply,

        [Parameter(ParameterSetName = 'Sync')]
        [switch] $Settings,

        [Parameter(Mandatory, ParameterSetName = 'Init')]
        [switch] $Init
    )

    if ($Init) {
        $null = Initialize-AgentGuidanceConfig -ConfigPath $ConfigPath
        return
    }

    foreach ($toolName in @('ssh', 'scp', 'git')) {
        if (-not (Get-Command $toolName -ErrorAction SilentlyContinue)) {
            throw "$toolName is required but is not on PATH. Install OpenSSH and Git, then open a new terminal."
        }
    }

    $config = Import-AgentGuidanceConfig -ConfigPath $ConfigPath
    $scope = Resolve-AgentGuidanceRunScope -Config $config -Settings:$Settings
    $targets = @(
        Resolve-AgentGuidanceTargets `
            -ConfiguredTarget $config.Targets `
            -ComputerName $ComputerName `
            -UseOverride:$PSBoundParameters.ContainsKey('ComputerName')
    )

    $files = @(
        if ($scope.IncludeFiles) {
            $config.Files
        }
    )

    foreach ($item in $files) {
        if (-not (Test-Path -LiteralPath $item.LocalPath -PathType Leaf)) {
            throw "Required source file for '$($item.Name)' is missing: $($item.LocalPath). Create the file or remove that mapping from $($config.ConfigPath)."
        }
        $item | Add-Member -NotePropertyName LocalHash -NotePropertyValue ((Get-FileHash -LiteralPath $item.LocalPath -Algorithm SHA256).Hash.ToLowerInvariant())
    }

    $inventory = @()
    try {
        $sourceSnapshot = if ($scope.IncludeSettings) {
            Get-AgentGuidanceCodexSourceSnapshot -ConfigPath $config.CodexConfig.LocalPath
        }
        else {
            $null
        }
        Write-Host "Agent guidance source: $($config.SourceLabel)" -ForegroundColor Cyan
        Write-Host "Config: $($config.ConfigPath)" -ForegroundColor DarkGray
        Write-Host $(if ($scope.IncludeSettings) { 'Mode: Codex settings projection' } else { 'Mode: instruction files' }) -ForegroundColor DarkGray
        $inventory = @(Get-AgentGuidanceInventory -ComputerName $targets -File $files)
        $reachableInventory = @($inventory | Where-Object { $_.Availability -eq 'Reachable' })
        $skippedInventory = @($inventory | Where-Object { $_.Availability -eq 'Unavailable' })
        if ($scope.IncludeSettings) {
            $inventory = @(Add-AgentGuidanceCodexConfigInventory `
                -Inventory $inventory `
                -CodexConfig $config.CodexConfig `
                -SourceSnapshot $sourceSnapshot)
        }
        Show-AgentGuidancePreview -Inventory $inventory -SourceLabel $config.SourceLabel
        $previewSummary = Get-AgentGuidancePreviewSummary -Inventory $inventory
        $operatorCommand = Get-AgentGuidanceOperatorCommand

        if ($reachableInventory.Count -eq 0) {
            $unavailableNames = @($skippedInventory.ComputerName) -join ', '
            throw "No configured targets are reachable. No files were changed. Unavailable targets: $unavailableNames."
        }

        if (-not $Apply) {
            Write-AgentGuidancePreviewSummary -Summary $previewSummary -CommandName $operatorCommand -Settings:$Settings
            return
        }

        $token = [guid]::NewGuid().ToString('N').Substring(0, 10)
        $backupSuffix = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $token
        $staged = @()

        try {
            Write-Host ''
            Write-Host 'Staging files on every reachable target before changing any destination...' -ForegroundColor Cyan
            foreach ($target in $reachableInventory) {
            if ($target.Platform -eq 'Unix') {
                $directories = @(
                    $target.Files |
                        ForEach-Object { Get-AgentGuidanceRemoteDirectory -RemotePath $_.RemotePath -Platform $target.Platform } |
                        Sort-Object -Unique
                )
                $directoryLiterals = @($directories | ForEach-Object { ConvertTo-AgentGuidanceShellLiteral -Value $_ })
                $mkdir = Invoke-AgentGuidanceSsh -ComputerName $target.ComputerName -RemoteCommand ('mkdir -p -- ' + ($directoryLiterals -join ' '))
                Assert-AgentGuidanceSuccess -Result $mkdir -Context "Creating guidance directories on $($target.ComputerName)"
            }

            foreach ($item in $target.Files) {
                $remoteDirectory = Get-AgentGuidanceRemoteDirectory -RemotePath $item.RemotePath -Platform $target.Platform
                $stageLeaf = if ($target.Platform -eq 'Windows') {
                    [IO.Path]::GetFileName($item.RemotePath)
                }
                else {
                    ($item.RemotePath -split '/')[-1]
                }
                if ($target.Platform -eq 'Windows') {
                    $stagePath = $remoteDirectory.TrimEnd('\') + '\.' + $stageLeaf + '.sync-' + $token + '.tmp'
                    Set-AgentGuidanceWindowsStage `
                        -ComputerName $target.ComputerName `
                        -StagePath $stagePath `
                        -LocalPath $item.LocalPath
                }
                else {
                    $stagePath = $remoteDirectory.TrimEnd('/') + '/.' + $stageLeaf + '.sync-' + $token + '.tmp'
                    $scpArguments = @(
                        '-q',
                        '-o', 'BatchMode=yes',
                        '-o', 'ConnectTimeout=8',
                        $item.LocalPath,
                        "$($target.ComputerName):$stagePath"
                    )
                    $copy = Invoke-AgentGuidanceNative -FilePath 'scp' -ArgumentList $scpArguments
                    Assert-AgentGuidanceSuccess -Result $copy -Context "Staging $($item.Name) on $($target.ComputerName)"
                }

                $stageHash = Get-AgentGuidanceRemoteHash `
                    -ComputerName $target.ComputerName `
                    -RemotePath $stagePath `
                    -Platform $target.Platform
                if ($stageHash -ne $item.LocalHash) {
                    throw "The staged $($item.Name) hash on $($target.ComputerName) does not match $($config.SourceLabel)."
                }

                $staged += [pscustomobject]@{
                    ComputerName = $target.ComputerName
                    Name = $item.Name
                    StagePath = $stagePath
                    DestinationPath = $item.RemotePath
                    ExpectedHash = $item.RemoteHash
                    WantedHash = $item.LocalHash
                    Platform = $target.Platform
                    NewFileMode = $item.NewFileMode
                }
            }
        }

        Write-Host 'Applying staged files...' -ForegroundColor Cyan
        $results = @()
        foreach ($item in $staged) {
            if ($item.Platform -eq 'Windows') {
                $commitScript = New-AgentGuidanceWindowsCommitScript `
                    -DestinationPath $item.DestinationPath `
                    -StagePath $item.StagePath `
                    -ExpectedHash $item.ExpectedHash `
                    -WantedHash $item.WantedHash `
                    -BackupSuffix $backupSuffix `
                    -DisplayName $item.Name
                $commit = Invoke-AgentGuidanceWindowsPowerShell `
                    -ComputerName $item.ComputerName `
                    -Script $commitScript
            }
            else {
                $commitCommand = New-AgentGuidanceCommitCommand `
                    -DestinationPath $item.DestinationPath `
                    -StagePath $item.StagePath `
                    -ExpectedHash $item.ExpectedHash `
                    -WantedHash $item.WantedHash `
                    -BackupSuffix $backupSuffix `
                    -DisplayName $item.Name `
                    -NewFileMode $item.NewFileMode
                $commit = Invoke-AgentGuidanceSsh -ComputerName $item.ComputerName -RemoteCommand $commitCommand
            }
            Assert-AgentGuidanceSuccess -Result $commit -Context "Applying $($item.Name) on $($item.ComputerName)"

            $resultLine = @($commit.Output | Where-Object { $_ -match '^(UPDATED|UNCHANGED)\|' }) | Select-Object -Last 1
            if (-not $resultLine) {
                throw "Applying $($item.Name) on $($item.ComputerName) returned no receipt."
            }

            $parts = $resultLine -split '\|'
            $results += [pscustomobject]@{
                ComputerName = $item.ComputerName
                File = $item.Name
                Status = $parts[0]
                Destination = $parts[2]
                Backup = if ($parts[0] -eq 'UPDATED') { $parts[3] } else { 'NONE' }
                SHA256 = if ($parts[0] -eq 'UPDATED') { $parts[4] } else { $parts[3] }
            }
        }

        Write-Host 'Verifying each destination independently...' -ForegroundColor Cyan
        foreach ($target in $reachableInventory) {
            foreach ($item in $target.Files) {
                $verifiedHash = Get-AgentGuidanceRemoteHash `
                    -ComputerName $target.ComputerName `
                    -RemotePath $item.RemotePath `
                    -Platform $target.Platform
                if ($verifiedHash -ne $item.LocalHash) {
                    throw "Verification failed for $($target.ComputerName):$($item.RemotePath)."
                }
            }
        }

        Write-Host ''
        $results | Format-Table ComputerName, File, Status, Backup, SHA256 -AutoSize
        Write-Host "Sync complete for $($reachableInventory.Count) reachable target(s). Existing sessions may retain their startup instructions; start a new session to load the new files." -ForegroundColor Green
        if ($skippedInventory.Count -gt 0) {
            Write-Warning "Unavailable targets were skipped and not changed: $(@($skippedInventory.ComputerName) -join ', ')."
        }
        }
        finally {
            foreach ($item in $staged) {
                if ($item.Platform -eq 'Windows') {
                    $stageLiteral = ConvertTo-AgentGuidancePowerShellLiteral -Value $item.StagePath
                    $cleanupScript = "if ([IO.File]::Exists($stageLiteral)) { [IO.File]::Delete($stageLiteral) }"
                    $null = Invoke-AgentGuidanceWindowsPowerShell -ComputerName $item.ComputerName -Script $cleanupScript
                }
                else {
                    $stageLiteral = ConvertTo-AgentGuidanceShellLiteral -Value $item.StagePath
                    $null = Invoke-AgentGuidanceSsh -ComputerName $item.ComputerName -RemoteCommand ('rm -f -- ' + $stageLiteral)
                }
            }
        }
    }
    finally {
        Remove-AgentGuidanceInventoryTemporaryFiles -Inventory $inventory
    }
}

Set-Alias -Name ag-sync -Value Sync-AgentGuidance
Export-ModuleMember -Function Sync-AgentGuidance -Alias ag-sync
