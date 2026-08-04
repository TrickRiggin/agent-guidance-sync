Set-StrictMode -Version Latest

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

    $detail = ($Result.Output -join [Environment]::NewLine).Trim()
    if (-not $detail) {
        $detail = 'No command output was returned.'
    }

    throw "$Context failed with exit code $($Result.ExitCode): $detail"
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
        throw "Agent guidance config is missing: $resolvedConfigPath. Copy config.example.json there and edit it for this machine."
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

    $fileProperty = $config.PSObject.Properties['files']
    if ($null -eq $fileProperty -or @($fileProperty.Value).Count -eq 0) {
        throw 'Agent guidance config must contain at least one file mapping.'
    }

    $configDirectory = [IO.Path]::GetDirectoryName($resolvedConfigPath)
    $nameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $destinationSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = @()
    foreach ($rawFile in @($fileProperty.Value)) {
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

    [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        SourceLabel = $sourceLabel
        Targets = $targets
        Files = $files
    }
}

function Get-AgentGuidanceRemotePlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ComputerName
    )

    $probe = Invoke-AgentGuidanceWindowsPowerShell `
        -ComputerName $ComputerName `
        -Script "[Console]::Out.WriteLine('AGENT_GUIDANCE_PLATFORM|Windows')"
    if ($probe.ExitCode -eq 0 -and ($probe.Output | Where-Object { $_ -eq 'AGENT_GUIDANCE_PLATFORM|Windows' })) {
        return 'Windows'
    }

    'Unix'
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
        [pscustomobject[]] $File
    )

    $inventory = @()
    foreach ($computer in $ComputerName) {
        Write-Host "Checking $computer..." -ForegroundColor Cyan

        $platform = Get-AgentGuidanceRemotePlatform -ComputerName $computer
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
            $preflightCommand = 'set -eu; for command_name in sha256sum diff cp mv mkdir chmod rm; do command -v "$command_name" >/dev/null; done; printf "ok\n"'
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
                LocalPath = $item.LocalPath
                LocalHash = $item.LocalHash
                RemotePath = $remotePath
                RemoteHash = $remoteHash
                Status = $status
                Platform = $platform
            }
        }

        $inventory += [pscustomobject]@{
            ComputerName = $computer
            RemoteHome = $remoteHome
            Platform = $platform
            Files = $remoteFiles
        }
    }

    $inventory
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

        foreach ($item in $target.Files) {
            if ($item.Status -eq 'Current') {
                Write-Host "  $($item.Name): current" -ForegroundColor Green
                continue
            }

            if ($item.Status -eq 'Missing') {
                Write-Host "  $($item.Name): missing; it will be created" -ForegroundColor Magenta
                continue
            }

            Write-Host "  $($item.Name): different" -ForegroundColor Magenta
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
        [string] $DisplayName
    )

    $template = @'
set -eu
destination=__DESTINATION__
stage=__STAGE__
expected=__EXPECTED__
wanted=__WANTED__
backup_suffix=__BACKUP_SUFFIX__
display_name=__DISPLAY_NAME__

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
    chmod 644 "$stage"
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
        Replace('__DISPLAY_NAME__', (ConvertTo-AgentGuidanceShellLiteral -Value $DisplayName))
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
    Previews or applies local agent-guidance files to remote hosts over SSH.

    .DESCRIPTION
    Reads source files, target SSH aliases, and home-relative destination paths
    from a JSON config. Without -Apply, shows differences and makes no changes.
    With -Apply, stages every file first, fences against concurrent remote edits,
    creates timestamped backups, replaces each file atomically, and verifies
    SHA-256 readback.

    .EXAMPLE
    Sync-AgentGuidance

    .EXAMPLE
    Sync-AgentGuidance -Apply

    .EXAMPLE
    Sync-AgentGuidance -ComputerName host-one -Apply

    .EXAMPLE
    Sync-AgentGuidance -ConfigPath ./lab-config.json
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern('^[A-Za-z0-9._-]+(?:@[A-Za-z0-9._-]+)?$')]
        [string[]] $ComputerName,

        [string] $ConfigPath = (Get-AgentGuidanceDefaultConfigPath),

        [switch] $Apply
    )

    foreach ($commandName in @('ssh', 'scp', 'git')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "$commandName is required but is not available on PATH."
        }
    }

    $config = Import-AgentGuidanceConfig -ConfigPath $ConfigPath
    $targets = @(
        Resolve-AgentGuidanceTargets `
            -ConfiguredTarget $config.Targets `
            -ComputerName $ComputerName `
            -UseOverride:$PSBoundParameters.ContainsKey('ComputerName')
    )

    $files = @($config.Files)

    foreach ($item in $files) {
        if (-not (Test-Path -LiteralPath $item.LocalPath -PathType Leaf)) {
            throw "Required source file is missing: $($item.LocalPath)"
        }
        $item | Add-Member -NotePropertyName LocalHash -NotePropertyValue ((Get-FileHash -LiteralPath $item.LocalPath -Algorithm SHA256).Hash.ToLowerInvariant())
    }

    Write-Host "Agent guidance source: $($config.SourceLabel)" -ForegroundColor Cyan
    Write-Host "Config: $($config.ConfigPath)" -ForegroundColor DarkGray
    $inventory = @(Get-AgentGuidanceInventory -ComputerName $targets -File $files)
    Show-AgentGuidancePreview -Inventory $inventory -SourceLabel $config.SourceLabel

    if (-not $Apply) {
        Write-Host ''
        Write-Host 'Preview complete. No files were changed. Run Sync-AgentGuidance -Apply to apply this exact source state.' -ForegroundColor Cyan
        return
    }

    $token = [guid]::NewGuid().ToString('N').Substring(0, 10)
    $backupSuffix = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $token
    $staged = @()

    try {
        Write-Host ''
        Write-Host 'Staging files on every target before changing any destination...' -ForegroundColor Cyan
        foreach ($target in $inventory) {
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
                if ($target.Platform -eq 'Windows') {
                    $stagePath = $remoteDirectory.TrimEnd('\') + '\.' + $item.Name + '.sync-' + $token + '.tmp'
                    Set-AgentGuidanceWindowsStage `
                        -ComputerName $target.ComputerName `
                        -StagePath $stagePath `
                        -LocalPath $item.LocalPath
                }
                else {
                    $stagePath = $remoteDirectory.TrimEnd('/') + '/.' + $item.Name + '.sync-' + $token + '.tmp'
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
                    -DisplayName $item.Name
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
        foreach ($target in $inventory) {
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
        Write-Host 'Sync complete. Existing Codex and Claude sessions may retain their startup instructions; start a new session to load the new files.' -ForegroundColor Green
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

Export-ModuleMember -Function Sync-AgentGuidance
