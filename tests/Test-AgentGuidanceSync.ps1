#Requires -Version 7.2

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $repositoryRoot 'AgentGuidanceSync/AgentGuidanceSync.psd1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('agent-guidance-sync-tests-' + [guid]::NewGuid().ToString('N'))
$script:passedCount = 0
$script:failures = @()

function Assert-Equal {
    param(
        [AllowNull()]
        $Expected,

        [AllowNull()]
        $Actual,

        [string] $Because = 'values should match'
    )

    if ($Expected -is [string] -and $Actual -is [string]) {
        if ($Expected -cne $Actual) {
            throw "$Because. Expected '$Expected', got '$Actual'."
        }
        return
    }
    if ($Expected -ne $Actual) {
        throw "$Because. Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [string] $Because = 'condition should be true'
    )

    if (-not $Condition) {
        throw $Because
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Script,

        [Parameter(Mandatory)]
        [string] $Pattern
    )

    try {
        & $Script
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected an error matching '$Pattern', got '$($_.Exception.Message)'."
        }
        return
    }
    throw "Expected an error matching '$Pattern', but no error was thrown."
}

function Test-Case {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Script
    )

    try {
        & $Script
        $script:passedCount++
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:failures += [pscustomobject]@{
            Name = $Name
            Message = $_.Exception.Message
        }
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-TestText {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Content
    )

    $parent = [IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($parent)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-TestHash {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-LocalCommitProgram {
    param(
        [Parameter(Mandatory)]
        [psmoduleinfo] $Module,

        [Parameter(Mandatory)]
        [string] $DestinationPath,

        [Parameter(Mandatory)]
        [string] $StagePath,

        [Parameter(Mandatory)]
        [string] $ExpectedHash,

        [Parameter(Mandatory)]
        [string] $WantedHash,

        [Parameter(Mandatory)]
        [string] $BackupSuffix
    )

    if ($IsWindows) {
        return & $Module {
            param($destination, $stage, $expected, $wanted, $suffix)
            New-AgentGuidanceWindowsCommitScript `
                -DestinationPath $destination `
                -StagePath $stage `
                -ExpectedHash $expected `
                -WantedHash $wanted `
                -BackupSuffix $suffix `
                -DisplayName 'test-file'
        } $DestinationPath $StagePath $ExpectedHash $WantedHash $BackupSuffix
    }

    & $Module {
        param($destination, $stage, $expected, $wanted, $suffix)
        New-AgentGuidanceCommitCommand `
            -DestinationPath $destination `
            -StagePath $stage `
            -ExpectedHash $expected `
            -WantedHash $wanted `
            -BackupSuffix $suffix `
            -DisplayName 'test-file'
    } $DestinationPath $StagePath $ExpectedHash $WantedHash $BackupSuffix
}

function Invoke-LocalCommitProgram {
    param(
        [Parameter(Mandatory)]
        [string] $Program
    )

    if ($IsWindows) {
        $encodedProgram = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Program))
        $output = @(& pwsh -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedProgram 2>&1)
        $exitCode = $LASTEXITCODE
        $outputText = @($output | ForEach-Object { $_.ToString() })
        if ($exitCode -ne 0) {
            throw ($outputText -join [Environment]::NewLine)
        }
        return $outputText
    }

    $output = @(& /bin/sh -c $Program 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }
    @($output | ForEach-Object { $_.ToString() })
}

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    Import-Module $manifestPath -Force -ErrorAction Stop
    $module = Get-Module AgentGuidanceSync -ErrorAction Stop

    Test-Case 'manifest and public command surface are valid' {
        Assert-Equal -Expected 'AgentGuidanceSync' -Actual $manifest.Name -Because 'manifest name should match the module folder'
        Assert-True -Condition ($manifest.Version.ToString() -match '^\d+\.\d+\.\d+$') -Because 'the module should use a three-part release version'
        $exportedCommands = @(Get-Command -Module AgentGuidanceSync)
        $exportedFunctions = @($exportedCommands | Where-Object { $_.CommandType -eq 'Function' } | ForEach-Object { $_.Name } | Sort-Object -Unique)
        $exportedAliases = @((Get-Module AgentGuidanceSync).ExportedAliases.Keys | Sort-Object)
        Assert-Equal -Expected 1 -Actual $exportedFunctions.Count -Because 'only one command should be public'
        Assert-Equal -Expected 'Sync-AgentGuidance' -Actual $exportedFunctions[0] -Because 'the sync command should be exported'
        Assert-Equal -Expected 1 -Actual $exportedAliases.Count -Because 'the short daily name should be an alias, not a second command'
        Assert-Equal -Expected 'ag-sync' -Actual $exportedAliases[0] -Because 'ag-sync should be the exported alias'
        Assert-Equal -Expected 'Sync-AgentGuidance' -Actual (Get-Command -Name ag-sync).ReferencedCommand.Name -Because 'ag-sync must resolve to Sync-AgentGuidance'
        $applyParameter = (Get-Command Sync-AgentGuidance).Parameters['apply']
        Assert-Equal -Expected 'Apply' -Actual $applyParameter.Name -Because 'PowerShell parameter names are case-insensitive; -apply is -Apply'
        Assert-Equal -Expected ([switch].FullName) -Actual $applyParameter.ParameterType.FullName -Because 'remote writes should require an explicit switch'
        $initParameter = (Get-Command Sync-AgentGuidance).Parameters['init']
        Assert-Equal -Expected 'Init' -Actual $initParameter.Name -Because '-init is the same switch as -Init'
        Assert-Equal -Expected ([switch].FullName) -Actual $initParameter.ParameterType.FullName -Because 'starter generation should be an explicit switch on the same command'
        $initIsOwnSet = @($initParameter.Attributes | Where-Object { $_ -is [Parameter] -and $_.ParameterSetName -eq 'Init' -and $_.Mandatory }).Count -ge 1
        Assert-True -Condition $initIsOwnSet -Because 'Init should be its own parameter set'
        $settingsParameter = (Get-Command Sync-AgentGuidance).Parameters['settings']
        Assert-Equal -Expected 'Settings' -Actual $settingsParameter.Name -Because '-settings is the same switch as -Settings'
        Assert-Equal -Expected ([switch].FullName) -Actual $settingsParameter.ParameterType.FullName -Because 'settings projection should require an explicit switch'
        $operatorCommand = & $module { Get-AgentGuidanceOperatorCommand }
        Assert-Equal -Expected 'ag-sync' -Actual $operatorCommand -Because 'operator hints should prefer the short daily name once the alias exists'
    }

    Test-Case 'npm package metadata matches the PowerShell module' {
        $packagePath = Join-Path $repositoryRoot 'package.json'
        $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
        Assert-Equal -Expected 'agent-guidance-sync' -Actual $package.name -Because 'the public npm name should match the repository'
        Assert-Equal -Expected $manifest.Version.ToString() -Actual $package.version -Because 'npm and PowerShell versions should be released together'
        Assert-Equal -Expected 'public' -Actual $package.publishConfig.access -Because 'the unscoped package should be explicitly public'

        $cliRelativePath = $package.bin.'agent-guidance-sync'
        Assert-Equal -Expected 'bin/agent-guidance-sync.ps1' -Actual $cliRelativePath -Because 'the long npm name should keep working'
        Assert-Equal -Expected $cliRelativePath -Actual $package.bin.'ag-sync' -Because 'ag-sync should be the same CLI, not a second implementation'
        $cliPath = Join-Path $repositoryRoot $cliRelativePath
        Assert-True -Condition (Test-Path -LiteralPath $cliPath -PathType Leaf) -Because 'the npm command target should exist'
        $cliText = Get-Content -LiteralPath $cliPath -Raw
        Assert-True -Condition ($cliText -match '\[switch\]\s+\$Init') -Because 'the npm CLI should forward -Init'
        Assert-True -Condition ($cliText -match '\[switch\]\s+\$Settings') -Because 'the npm CLI should forward -Settings'
        Assert-True -Condition ($cliText -match '\[switch\]\s+\$NonInteractive') -Because 'the npm CLI should forward -NonInteractive'
    }

    Test-Case 'literal escaping and remote directory parsing are platform-safe' {
        $shellLiteral = & $module { ConvertTo-AgentGuidanceShellLiteral -Value "a'b" }
        $expectedShellLiteral = @'
'a'"'"'b'
'@
        Assert-Equal -Expected $expectedShellLiteral -Actual $shellLiteral -Because 'POSIX shell quotes should be escaped'

        $powerShellLiteral = & $module { ConvertTo-AgentGuidancePowerShellLiteral -Value "a'b" }
        Assert-Equal -Expected "'a''b'" -Actual $powerShellLiteral -Because 'PowerShell quotes should be escaped'

        $unixDirectory = & $module { Get-AgentGuidanceRemoteDirectory -RemotePath '/home/demo/.codex/AGENTS.md' -Platform Unix }
        Assert-Equal -Expected '/home/demo/.codex' -Actual $unixDirectory
        $windowsDirectory = & $module { Get-AgentGuidanceRemoteDirectory -RemotePath 'C:\Users\demo\.codex\AGENTS.md' -Platform Windows }
        Assert-Equal -Expected 'C:\Users\demo\.codex' -Actual $windowsDirectory
    }

    Test-Case 'config resolves relative sources and keeps destinations home-relative' {
        $caseRoot = Join-Path $temporaryRoot 'valid-config'
        $sourcePath = Join-Path $caseRoot 'sources/AGENTS.md'
        Set-TestText -Path $sourcePath -Content "test guidance`n"
        $configPath = Join-Path $caseRoot 'config.json'
        $configJson = [ordered]@{
            sourceLabel = 'test-source'
            targets = @('host-one', 'demo@host-two')
            files = @(
                [ordered]@{
                    sourcePath = 'sources/AGENTS.md'
                    destinationPath = '.codex\AGENTS.md'
                }
            )
        } | ConvertTo-Json -Depth 5
        Set-TestText -Path $configPath -Content $configJson

        $config = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        Assert-Equal -Expected 'test-source' -Actual $config.SourceLabel
        Assert-Equal -Expected 2 -Actual $config.Targets.Count
        Assert-Equal -Expected ([IO.Path]::GetFullPath($sourcePath)) -Actual $config.Files[0].LocalPath
        Assert-Equal -Expected '.codex/AGENTS.md' -Actual $config.Files[0].RemoteRelativePath
        Assert-Equal -Expected 'AGENTS.md' -Actual $config.Files[0].Name
        Assert-Equal -Expected 0 -Actual @($config.Files[0].AssignedTargets).Count -Because 'omitted file targets still apply to every host'
    }

    Test-Case 'shipped starter and multi-harness configs remain valid and narrowly scoped' {
        $starterPath = Join-Path $repositoryRoot 'config.example.json'
        $starter = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $starterPath
        Assert-Equal -Expected 2 -Actual $starter.Files.Count -Because 'the starter should stay focused on Codex and Claude'

        $multiHarnessPath = Join-Path $repositoryRoot 'config.multi-harness.example.json'
        $multiHarness = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $multiHarnessPath
        Assert-Equal -Expected 6 -Actual $multiHarness.Files.Count -Because 'the broader preset should cover six verified harnesses'

        $expectedDestinations = @(
            '.codex/AGENTS.md',
            '.claude/CLAUDE.md',
            '.grok/AGENTS.md',
            '.pi/agent/AGENTS.md',
            '.omp/agent/AGENTS.md',
            '.config/opencode/AGENTS.md'
        )
        $actualDestinations = @($multiHarness.Files | ForEach-Object { $_.RemoteRelativePath })
        Assert-Equal `
            -Expected ($expectedDestinations -join '|') `
            -Actual ($actualDestinations -join '|') `
            -Because 'every harness should map to its documented native path'

        $forbiddenState = '(?i)(auth\.(json|ya?ml)|settings\.(json|ya?ml)|config\.ya?ml|models?\.(json|ya?ml)|sessions?|RULES\.md|id_(rsa|ed25519))'
        for ($index = 0; $index -lt $multiHarness.Files.Count; $index++) {
            $file = $multiHarness.Files[$index]
            $sourcePath = $file.LocalPath.Replace('\', '/')
            $expectedSourceSuffix = '/' + $expectedDestinations[$index]
            Assert-True `
                -Condition $sourcePath.EndsWith($expectedSourceSuffix, [StringComparison]::OrdinalIgnoreCase) `
                -Because "each harness should keep a distinct native source file: $sourcePath"

            $mappingText = $file.LocalPath.Replace('\', '/') + '|' + $file.RemoteRelativePath
            Assert-True `
                -Condition ($mappingText -notmatch $forbiddenState) `
                -Because "the shipped preset must not include credentials, settings, models, sessions, keys, or sticky rules: $mappingText"
        }

        $portablePath = Join-Path $repositoryRoot 'config.codex-portable.example.json'
        $portable = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $portablePath
        Assert-True -Condition ($null -ne $portable.CodexConfig) -Because 'the portable preset should enable semantic Codex config projection'
        Assert-Equal -Expected '.codex/config.toml' -Actual $portable.CodexConfig.RemoteRelativePath
        Assert-Equal -Expected 24 -Actual $portable.CodexConfig.PortableKeys.Count -Because 'the example should own only reviewed portable settings'
        Assert-Equal -Expected 1 -Actual $portable.CodexConfig.WindowsKeys.Count -Because 'Windows sandbox implementation should be platform-scoped'
        Assert-Equal -Expected 5 -Actual $portable.CodexConfig.RemoveKeys.Count -Because 'the example should remove only reviewed stale keys'

        $catalogDestinations = @(& $module { @($script:AgentGuidanceKnownFiles | ForEach-Object { $_.DestinationPath }) })
        Assert-Equal `
            -Expected ($expectedDestinations -join '|') `
            -Actual ($catalogDestinations -join '|') `
            -Because 'the Init catalog should stay aligned with the verified multi-harness destinations'
    }

    Test-Case 'Init selects existing local files and falls back to the two-file starter' {
        $profileRoot = Join-Path $temporaryRoot 'init-profile'
        $claudePath = Join-Path $profileRoot '.claude/CLAUDE.md'
        $grokPath = Join-Path $profileRoot '.grok/AGENTS.md'
        $openCodePath = Join-Path $profileRoot '.config/opencode/AGENTS.md'
        Set-TestText -Path $claudePath -Content 'claude guidance'
        Set-TestText -Path $grokPath -Content 'grok guidance'
        Set-TestText -Path $openCodePath -Content 'opencode guidance'

        $selected = @(& $module { param($root) Select-AgentGuidanceStarterFiles -ProfileRoot $root } $profileRoot)
        Assert-Equal -Expected 3 -Actual $selected.Count -Because 'only files that exist locally should be included'
        Assert-Equal -Expected 'Claude CLAUDE.md' -Actual $selected[0].Name
        Assert-Equal -Expected 'Grok AGENTS.md' -Actual $selected[1].Name
        Assert-Equal -Expected 'OpenCode AGENTS.md' -Actual $selected[2].Name
        Assert-True -Condition (-not $selected[0].Fallback) -Because 'detected files are not the fallback starter'

        $emptyProfile = Join-Path $temporaryRoot 'init-empty-profile'
        New-Item -ItemType Directory -Path $emptyProfile | Out-Null
        $fallback = @(& $module { param($root) Select-AgentGuidanceStarterFiles -ProfileRoot $root } $emptyProfile)
        Assert-Equal -Expected 2 -Actual $fallback.Count -Because 'the empty-profile starter should stay focused on Codex and Claude'
        Assert-Equal -Expected 'Codex AGENTS.md' -Actual $fallback[0].Name
        Assert-Equal -Expected 'Claude CLAUDE.md' -Actual $fallback[1].Name
        Assert-True -Condition $fallback[0].Fallback -Because 'missing local files should use the documented starter pair'
    }

    Test-Case 'Init writes a starter config and refuses to overwrite it' {
        $profileRoot = Join-Path $temporaryRoot 'init-write-profile'
        Set-TestText -Path (Join-Path $profileRoot '.codex/AGENTS.md') -Content 'codex guidance'
        $configPath = Join-Path $temporaryRoot 'init-write/config.json'
        $sshConfigPath = Join-Path $temporaryRoot 'init-write/ssh-config'
        Set-TestText -Path $sshConfigPath -Content @"
Host lab-pi work-box
    User demo
Host *.example.com
    User wildcard
# Host commented-out
Host github.com
"@

        $result = & $module {
            param($path, $root, $sshPath)
            Initialize-AgentGuidanceConfig -ConfigPath $path -ProfileRoot $root -SshConfigPath $sshPath
        } $configPath $profileRoot $sshConfigPath

        Assert-Equal -Expected ([IO.Path]::GetFullPath($configPath)) -Actual $result.ConfigPath
        Assert-True -Condition (Test-Path -LiteralPath $configPath -PathType Leaf) -Because 'Init should write the starter file'
        Assert-Equal -Expected 1 -Actual $result.Files.Count
        Assert-Equal -Expected 'Codex AGENTS.md' -Actual $result.Files[0].Name
        Assert-True -Condition (-not $result.UsedFallback)
        Assert-Equal -Expected 'lab-pi|work-box|github.com' -Actual ($result.SshAliases -join '|') -Because 'SSH hints should include concrete Host aliases and skip wildcards'

        $imported = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        Assert-Equal -Expected 1 -Actual $imported.Files.Count
        Assert-Equal -Expected '.codex/AGENTS.md' -Actual $imported.Files[0].RemoteRelativePath
        Assert-Equal -Expected 2 -Actual $imported.Targets.Count
        Assert-Equal -Expected 'host-one' -Actual $imported.Targets[0]

        Assert-Throws -Pattern 'already exists' -Script {
            & $module {
                param($path, $root)
                Initialize-AgentGuidanceConfig -ConfigPath $path -ProfileRoot $root
            } $configPath $profileRoot
        }
    }

    Test-Case 'missing config points at -Init instead of a nearby example file' {
        $missingPath = Join-Path $temporaryRoot 'does-not-exist/config.json'
        Assert-Throws -Pattern '(?i)-init' -Script {
            & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $missingPath
        }
    }

    Test-Case 'preview summary counts reachable, skipped, and change classes' {
        $summary = & $module {
            $inventory = @(
                [pscustomobject]@{
                    ComputerName = 'online-host'
                    Availability = 'Reachable'
                    Files = @(
                        [pscustomobject]@{ Status = 'Current' }
                        [pscustomobject]@{ Status = 'Different' }
                        [pscustomobject]@{ Status = 'Missing' }
                    )
                }
                [pscustomobject]@{
                    ComputerName = 'offline-host'
                    Availability = 'Unavailable'
                    Files = @()
                }
            )
            Get-AgentGuidancePreviewSummary -Inventory $inventory
        }

        Assert-Equal -Expected 1 -Actual $summary.ReachableCount
        Assert-Equal -Expected 1 -Actual $summary.SkippedCount
        Assert-Equal -Expected 'offline-host' -Actual $summary.SkippedNames[0]
        Assert-Equal -Expected 1 -Actual $summary.CurrentCount
        Assert-Equal -Expected 1 -Actual $summary.DifferentCount
        Assert-Equal -Expected 1 -Actual $summary.MissingCount
        Assert-Equal -Expected 2 -Actual $summary.ChangeCount
    }

    Test-Case 'preview summary handles all reachable hosts without skipped names' {
        $summary = & $module {
            Get-AgentGuidancePreviewSummary -Inventory @(
                [pscustomobject]@{
                    ComputerName = 'online-host'
                    Availability = 'Reachable'
                    Files = @([pscustomobject]@{ Status = 'Different' })
                }
            )
        }

        Assert-Equal -Expected 1 -Actual $summary.ReachableCount
        Assert-Equal -Expected 0 -Actual $summary.SkippedCount
        Assert-True -Condition ($summary.SkippedNames -is [array]) -Because 'skipped names should remain an array when empty'
        Assert-Equal -Expected 0 -Actual $summary.SkippedNames.Count
        Assert-Equal -Expected 1 -Actual $summary.ChangeCount
        Assert-Equal -Expected 1 -Actual $summary.ComparedCount
    }

    Test-Case 'preview summary handles an empty inventory' {
        $summary = & $module { Get-AgentGuidancePreviewSummary -Inventory @() }

        Assert-Equal -Expected 0 -Actual $summary.ReachableCount
        Assert-Equal -Expected 0 -Actual $summary.SkippedCount
        Assert-Equal -Expected 0 -Actual $summary.SkippedNames.Count
        Assert-Equal -Expected 0 -Actual $summary.ChangeCount
        Assert-Equal -Expected 0 -Actual $summary.ComparedCount
    }

    Test-Case 'Init cannot be combined with remote-write or target-override switches' {
        $errorRecord = $null
        try {
            Sync-AgentGuidance -Init -Apply -ErrorAction Stop
        }
        catch {
            $errorRecord = $_
        }
        Assert-True -Condition ($null -ne $errorRecord) -Because '-Init -Apply should fail before any work starts'
        Assert-True -Condition ($errorRecord.Exception.Message -match 'Parameter set|parameter set') -Because 'PowerShell should reject the conflicting parameter set'

        $settingsConflict = $null
        try {
            Sync-AgentGuidance -Init -Settings -ErrorAction Stop
        }
        catch {
            $settingsConflict = $_
        }
        Assert-True -Condition ($null -ne $settingsConflict) -Because '-Init -Settings should fail before any work starts'
        Assert-True -Condition ($settingsConflict.Exception.Message -match 'Parameter set|parameter set') -Because 'starter generation must not enter the settings path'
    }

    Test-Case 'default runs exclude settings and -settings excludes instruction files' {
        $fileOnly = & $module {
            Resolve-AgentGuidanceRunScope -Config ([pscustomobject]@{
                ConfigPath = 'C:\temp\config.json'
                Files = @([pscustomobject]@{ Name = 'AGENTS.md' })
                CodexConfig = [pscustomobject]@{ Name = 'Codex config.toml settings' }
            })
        }
        Assert-True -Condition $fileOnly.IncludeFiles -Because 'the default run should copy instruction files'
        Assert-True -Condition (-not $fileOnly.IncludeSettings) -Because 'codexConfig must stay inert without -settings'

        $settingsOnly = & $module {
            Resolve-AgentGuidanceRunScope -Config ([pscustomobject]@{
                ConfigPath = 'C:\temp\config.json'
                Files = @([pscustomobject]@{ Name = 'AGENTS.md' })
                CodexConfig = [pscustomobject]@{ Name = 'Codex config.toml settings' }
            }) -Settings
        }
        Assert-True -Condition (-not $settingsOnly.IncludeFiles) -Because '-settings should not copy instruction files'
        Assert-True -Condition $settingsOnly.IncludeSettings -Because '-settings should enable the Codex projection'

        Assert-Throws -Pattern '(?i)-settings' -Script {
            & $module {
                Resolve-AgentGuidanceRunScope -Config ([pscustomobject]@{
                    ConfigPath = 'C:\temp\config.json'
                    Files = @([pscustomobject]@{ Name = 'AGENTS.md' })
                    CodexConfig = $null
                }) -Settings
            }
        }

        Assert-Throws -Pattern '(?i)-settings' -Script {
            & $module {
                Resolve-AgentGuidanceRunScope -Config ([pscustomobject]@{
                    ConfigPath = 'C:\temp\config.json'
                    Files = @()
                    CodexConfig = [pscustomobject]@{ Name = 'Codex config.toml settings' }
                })
            }
        }
    }

    Test-Case 'Sync-AgentGuidance -Init writes through the public command' {
        $configPath = Join-Path $temporaryRoot 'public-init/config.json'
        Sync-AgentGuidance -Init -NonInteractive -ConfigPath $configPath
        Assert-True -Condition (Test-Path -LiteralPath $configPath -PathType Leaf) -Because 'the public command should write the starter'
        $imported = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        Assert-True -Condition ($imported.Files.Count -ge 1 -and $imported.Files.Count -le 6) -Because 'Init should write only known instruction mappings'
        foreach ($file in $imported.Files) {
            Assert-True -Condition ($file.RemoteRelativePath -match 'AGENTS\.md$|CLAUDE\.md$') -Because 'Init must not invent destinations outside the known catalog'
        }
        Assert-Throws -Pattern 'already exists' -Script {
            Sync-AgentGuidance -Init -NonInteractive -ConfigPath $configPath
        }
    }

    Test-Case 'file mappings can be limited to named hosts' {
        $caseRoot = Join-Path $temporaryRoot 'per-host-files'
        $claudePath = Join-Path $caseRoot 'CLAUDE.md'
        $grokPath = Join-Path $caseRoot 'AGENTS.md'
        Set-TestText -Path $claudePath -Content 'claude'
        Set-TestText -Path $grokPath -Content 'grok'
        $configPath = Join-Path $caseRoot 'config.json'
        $configJson = [ordered]@{
            targets = @('maple', 'spark')
            files = @(
                [ordered]@{
                    name = 'Claude CLAUDE.md'
                    sourcePath = $claudePath
                    destinationPath = '.claude/CLAUDE.md'
                    targets = @('maple', 'spark')
                }
                [ordered]@{
                    name = 'Grok AGENTS.md'
                    sourcePath = $grokPath
                    destinationPath = '.grok/AGENTS.md'
                    targets = @('maple')
                }
            )
        } | ConvertTo-Json -Depth 5
        Set-TestText -Path $configPath -Content $configJson

        $config = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        $mapleFiles = @(& $module { param($files) Select-AgentGuidanceFilesForTarget -File $files -ComputerName 'maple' } $config.Files)
        $sparkFiles = @(& $module { param($files) Select-AgentGuidanceFilesForTarget -File $files -ComputerName 'spark' } $config.Files)
        Assert-Equal -Expected 2 -Actual $mapleFiles.Count
        Assert-Equal -Expected 1 -Actual $sparkFiles.Count
        Assert-Equal -Expected 'Claude CLAUDE.md' -Actual $sparkFiles[0].Name

        $unknownPath = Join-Path $caseRoot 'unknown.json'
        $unknownJson = [ordered]@{
            targets = @('maple')
            files = @(
                [ordered]@{
                    sourcePath = $claudePath
                    destinationPath = '.claude/CLAUDE.md'
                    targets = @('willow')
                }
            )
        } | ConvertTo-Json -Depth 5
        Set-TestText -Path $unknownPath -Content $unknownJson
        Assert-Throws -Pattern 'not in the config targets list' -Script {
            & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $unknownPath
        }
    }

    Test-Case 'init plan toggles hosts and keeps per-host agent selections' {
        $presence = & $module {
            ConvertFrom-AgentGuidancePresenceOutput `
                -Output @('PRESENT|.claude', 'MISSING|.grok', 'PRESENT|.config/opencode') `
                -RelativeDirectory @('.claude', '.grok', '.config/opencode')
        }
        Assert-True -Condition $presence['.claude']
        Assert-True -Condition (-not $presence['.grok'])
        Assert-True -Condition $presence['.config/opencode']

        $plan = @(
            [pscustomobject]@{
                ComputerName = 'maple'
                Availability = 'Reachable'
                Failure = $null
                Agents = @(
                    [pscustomobject]@{ Name = 'Claude CLAUDE.md'; SourcePath = '~/.claude/CLAUDE.md'; DestinationPath = '.claude/CLAUDE.md'; Selected = $true }
                    [pscustomobject]@{ Name = 'Grok AGENTS.md'; SourcePath = '~/.grok/AGENTS.md'; DestinationPath = '.grok/AGENTS.md'; Selected = $true }
                    [pscustomobject]@{ Name = 'OpenCode AGENTS.md'; SourcePath = '~/.config/opencode/AGENTS.md'; DestinationPath = '.config/opencode/AGENTS.md'; Selected = $true }
                )
            }
            [pscustomobject]@{
                ComputerName = 'spark'
                Availability = 'Reachable'
                Failure = $null
                Agents = @(
                    [pscustomobject]@{ Name = 'Claude CLAUDE.md'; SourcePath = '~/.claude/CLAUDE.md'; DestinationPath = '.claude/CLAUDE.md'; Selected = $true }
                    [pscustomobject]@{ Name = 'Grok AGENTS.md'; SourcePath = '~/.grok/AGENTS.md'; DestinationPath = '.grok/AGENTS.md'; Selected = $true }
                    [pscustomobject]@{ Name = 'OpenCode AGENTS.md'; SourcePath = '~/.config/opencode/AGENTS.md'; DestinationPath = '.config/opencode/AGENTS.md'; Selected = $true }
                )
            }
        )

        $rows = @(& $module { param($hosts) Get-AgentGuidanceInitPlanRows -HostPlan $hosts } $plan)
        Assert-Equal -Expected 'Confirm' -Actual $rows[-1].Kind -Because 'the last row should be an explicit confirm action'
        $summary = & $module { param($hosts) Get-AgentGuidanceInitPlanSummary -HostPlan $hosts } $plan
        Assert-True -Condition ($summary -match '2 hosts selected') -Because 'the confirm footer should count selected hosts'
        $sparkHost = $rows | Where-Object { $_.Kind -eq 'Host' -and $_.Host.ComputerName -eq 'spark' } | Select-Object -First 1
        $sparkGrok = $rows | Where-Object { $_.Kind -eq 'Agent' -and $_.Host.ComputerName -eq 'spark' -and $_.Agent.Name -eq 'Grok AGENTS.md' } | Select-Object -First 1
        $sparkOpenCode = $rows | Where-Object { $_.Kind -eq 'Agent' -and $_.Host.ComputerName -eq 'spark' -and $_.Agent.Name -eq 'OpenCode AGENTS.md' } | Select-Object -First 1
        & $module { param($row) Invoke-AgentGuidanceInitPlanToggle -Row $row } $sparkGrok
        & $module { param($row) Invoke-AgentGuidanceInitPlanToggle -Row $row } $sparkOpenCode
        Assert-True -Condition (-not $sparkGrok.Agent.Selected)
        Assert-True -Condition (-not $sparkOpenCode.Agent.Selected)
        Assert-Equal -Expected '-' -Actual (& $module { param($hostItem) Get-AgentGuidanceHostSelectionMark -HostItem $hostItem } $sparkHost.Host)

        $document = & $module { param($hosts) ConvertTo-AgentGuidanceConfigDocumentFromPlan -SourceLabel 'OAK' -HostPlan $hosts } $plan
        $grokFile = @($document.files | Where-Object { $_.name -eq 'Grok AGENTS.md' })[0]
        $openCodeFile = @($document.files | Where-Object { $_.name -eq 'OpenCode AGENTS.md' })[0]
        $claudeFile = @($document.files | Where-Object { $_.name -eq 'Claude CLAUDE.md' })[0]
        Assert-Equal -Expected 'maple' -Actual ($grokFile.targets -join ',')
        Assert-Equal -Expected 'maple' -Actual ($openCodeFile.targets -join ',')
        Assert-Equal -Expected 'maple,spark' -Actual ($claudeFile.targets -join ',')

        & $module { param($row) Invoke-AgentGuidanceInitPlanToggle -Row $row } $sparkHost
        Assert-True -Condition $sparkGrok.Agent.Selected -Because 'selecting a host should re-check every agent on that host'
    }

    Test-Case 'exact-copy mappings cannot bypass sensitive-state boundaries' {
        $caseRoot = Join-Path $temporaryRoot 'reserved-destinations'
        $sourcePath = Join-Path $caseRoot 'source.txt'
        Set-TestText -Path $sourcePath -Content 'do not copy this as state'
        foreach ($destination in @('.codex/config.toml', '.codex/auth.json', '.codex/sessions/thread.jsonl', '.codex/state.sqlite')) {
            $configPath = Join-Path $caseRoot (($destination -replace '[^A-Za-z0-9]', '-') + '.json')
            $configJson = [ordered]@{
                targets = @('host-one')
                files = @([ordered]@{ sourcePath = $sourcePath; destinationPath = $destination })
            } | ConvertTo-Json -Depth 5
            Set-TestText -Path $configPath -Content $configJson
            Assert-Throws -Pattern 'Exact-copy mappings cannot target' -Script {
                & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
            }
        }
    }

    Test-Case 'Codex projection rejects secret-bearing and capability key paths' {
        $caseRoot = Join-Path $temporaryRoot 'unsafe-codex-key'
        $sourceConfig = Join-Path $caseRoot 'config.toml'
        Set-TestText -Path $sourceConfig -Content 'model = "gpt-5"'
        $configPath = Join-Path $caseRoot 'config.json'
        $configJson = [ordered]@{
            targets = @('host-one')
            codexConfig = [ordered]@{
                sourcePath = $sourceConfig
                keyPaths = @('mcp_servers.private.command')
            }
        } | ConvertTo-Json -Depth 5
        Set-TestText -Path $configPath -Content $configJson
        Assert-Throws -Pattern 'safe portable projection allowlist' -Script {
            & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        }
    }

    Test-Case 'semantic Codex projection preserves target-local state and previews only owned keys' {
        if (-not (Get-Command codex -CommandType Application -ErrorAction SilentlyContinue)) {
            Write-Host '      Codex CLI unavailable; semantic materialization probe skipped.' -ForegroundColor DarkYellow
            return
        }

        $probe = & $module {
            $utf8 = [Text.UTF8Encoding]::new($false)
            $sourceText = @'
model_reasoning_effort = "high"
service_tier = "fast"

[desktop]
followUpQueueMode = "steer"
sansFontSize = 14
'@
            $targetOneText = @'
model_reasoning_effort = "max"
service_tier = "default"

[features]
js_repl = false

[projects.'C:/private-one']
trust_level = "trusted"

[mcp_servers.private]
command = "SECRET-CANARY-ONE"
'@
            $targetTwoText = @'
model_reasoning_effort = "low"
service_tier = "default"

[projects.'D:/private-two']
trust_level = "trusted"

[mcp_servers.private]
command = "SECRET-CANARY-TWO"
'@
            $sourceHome = New-AgentGuidanceTemporaryCodexHome -ConfigBytes $utf8.GetBytes($sourceText)
            $candidateOne = $null
            $candidateTwo = $null
            $candidateMissing = $null
            try {
                $source = Get-AgentGuidanceCodexSnapshot -CodexHome $sourceHome
                $definition = [pscustomobject]@{
                    PortableKeys = @('model_reasoning_effort', 'service_tier', 'desktop.followUpQueueMode', 'desktop.sansFontSize')
                    WindowsKeys = @()
                    RemoveKeys = @('features.js_repl')
                }
                $candidateOne = New-AgentGuidanceCodexCandidate `
                    -TargetConfigBytes $utf8.GetBytes($targetOneText) `
                    -SourceSnapshot $source `
                    -CodexConfig $definition `
                    -Platform Windows
                $candidateTwo = New-AgentGuidanceCodexCandidate `
                    -TargetConfigBytes $utf8.GetBytes($targetTwoText) `
                    -SourceSnapshot $source `
                    -CodexConfig $definition `
                    -Platform Unix
                $candidateMissing = New-AgentGuidanceCodexCandidate `
                    -TargetConfigBytes ([byte[]]::new(0)) `
                    -SourceSnapshot $source `
                    -CodexConfig $definition `
                    -Platform Unix
                $oneText = [IO.File]::ReadAllText($candidateOne.LocalPath)
                $twoText = [IO.File]::ReadAllText($candidateTwo.LocalPath)
                $missingText = [IO.File]::ReadAllText($candidateMissing.LocalPath)
                $previewInventory = @([pscustomobject]@{
                    ComputerName = 'test-host'
                    Platform = 'Windows'
                    Files = @([pscustomobject]@{
                        Name = 'Codex config.toml settings'
                        Kind = 'CodexConfig'
                        Status = 'Different'
                        Changes = $candidateOne.Changes
                        LocalPath = $candidateOne.LocalPath
                    })
                })
                $preview = @(& {
                    Show-AgentGuidancePreview -Inventory $previewInventory -SourceLabel 'test-source'
                } 6>&1 | ForEach-Object { $_.ToString() }) -join "`n"

                [pscustomobject]@{
                    OnePreserved = $oneText.Contains('SECRET-CANARY-ONE') -and $oneText.Contains('C:/private-one')
                    TwoPreserved = $twoText.Contains('SECRET-CANARY-TWO') -and $twoText.Contains('D:/private-two')
                    CanariesIsolated = -not $oneText.Contains('SECRET-CANARY-TWO') -and -not $twoText.Contains('SECRET-CANARY-ONE')
                    RemovedDeadKey = -not $oneText.Contains('js_repl')
                    NumberPreserved = $oneText -match '(?m)^sansFontSize\s*=\s*14\s*$' -and -not $oneText.Contains('serde_json')
                    MissingConfigCreated = $missingText.Contains('model_reasoning_effort = "high"') -and $missingText.Contains('followUpQueueMode = "steer"')
                    PreviewShowsOwnedKey = $preview.Contains('model_reasoning_effort')
                    PreviewHidesCanary = -not $preview.Contains('SECRET-CANARY')
                }
            }
            finally {
                foreach ($candidate in @($candidateOne, $candidateTwo, $candidateMissing)) {
                    if ($null -ne $candidate -and (Test-Path -LiteralPath $candidate.TemporaryDirectory)) {
                        Remove-AgentGuidanceTemporaryCodexHome -Path $candidate.TemporaryDirectory
                    }
                }
                Remove-AgentGuidanceTemporaryCodexHome -Path $sourceHome
            }
        }

        Assert-True -Condition $probe.OnePreserved -Because 'target one project and MCP state should survive byte-for-byte'
        Assert-True -Condition $probe.TwoPreserved -Because 'target two project and MCP state should survive byte-for-byte'
        Assert-True -Condition $probe.CanariesIsolated -Because 'target-local state must never cross between candidates'
        Assert-True -Condition $probe.RemovedDeadKey -Because 'reviewed removed keys should be deleted semantically'
        Assert-True -Condition $probe.NumberPreserved -Because 'TOML numbers should round-trip as numbers rather than protocol wrapper objects'
        Assert-True -Condition $probe.MissingConfigCreated -Because 'a missing target config should become a valid projected config'
        Assert-True -Condition $probe.PreviewShowsOwnedKey -Because 'preview should identify projected settings'
        Assert-True -Condition $probe.PreviewHidesCanary -Because 'preview must not render unowned config content'
    }

    Test-Case 'unsafe remote destinations are rejected' {
        foreach ($unsafePath in @('/tmp/AGENTS.md', 'C:\Temp\AGENTS.md', '../AGENTS.md', '.codex/../AGENTS.md', '~/.codex/AGENTS.md', '.codex//AGENTS.md')) {
            Assert-Throws -Pattern 'Destination paths' -Script {
                & $module { param($path) ConvertTo-AgentGuidanceRemoteRelativePath -Path $path } $unsafePath
            }
        }
    }

    Test-Case 'invalid and duplicate SSH targets are rejected before networking' {
        Assert-Throws -Pattern 'Invalid SSH target' -Script {
            & $module { Assert-AgentGuidanceComputerName -ComputerName 'host one' }
        }

        $caseRoot = Join-Path $temporaryRoot 'duplicate-targets'
        $sourcePath = Join-Path $caseRoot 'AGENTS.md'
        Set-TestText -Path $sourcePath -Content 'test'
        $configPath = Join-Path $caseRoot 'config.json'
        $configJson = [ordered]@{
            targets = @('Host-One', 'host-one')
            files = @(
                [ordered]@{
                    sourcePath = $sourcePath
                    destinationPath = '.codex/AGENTS.md'
                }
            )
        } | ConvertTo-Json -Depth 5
        Set-TestText -Path $configPath -Content $configJson
        Assert-Throws -Pattern 'Duplicate SSH target' -Script {
            & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $configPath
        }
    }

    Test-Case 'a single configured or overridden target remains an array' {
        $configuredTargets = @(& $module { Resolve-AgentGuidanceTargets -ConfiguredTarget @('only-host') })
        Assert-Equal -Expected 1 -Actual $configuredTargets.Count
        Assert-Equal -Expected 'only-host' -Actual $configuredTargets[0]

        $overriddenTargets = @(& $module {
            Resolve-AgentGuidanceTargets -ConfiguredTarget @('ignored-host') -ComputerName @('override-host') -UseOverride
        })
        Assert-Equal -Expected 1 -Actual $overriddenTargets.Count
        Assert-Equal -Expected 'override-host' -Actual $overriddenTargets[0]
    }

    Test-Case 'native transport failures are surfaced with their evidence' {
        Assert-Throws -Pattern 'connection refused' -Script {
            & $module {
                $result = [pscustomobject]@{
                    ExitCode = 255
                    Output = @('ssh: connection refused')
                }
                Assert-AgentGuidanceSuccess -Result $result -Context 'Connecting to test-host'
            }
        }
    }

    Test-Case 'SSH probe classification skips only hard network failures' {
        $classification = & $module {
            $timeout = Resolve-AgentGuidanceTargetConnection -Probe ([pscustomobject]@{
                ExitCode = 255
                Output = @('ssh: connect to host offline-host port 22: Connection timed out')
            })
            $authFailure = Resolve-AgentGuidanceTargetConnection -Probe ([pscustomobject]@{
                ExitCode = 255
                Output = @('offline-host: Permission denied (publickey).')
            })
            $windows = Resolve-AgentGuidanceTargetConnection -Probe ([pscustomobject]@{
                ExitCode = 0
                Output = @('AGENT_GUIDANCE_PLATFORM|Windows')
            })
            [pscustomobject]@{
                TimeoutAvailability = $timeout.Availability
                TimeoutReason = $timeout.Failure
                AuthAvailability = $authFailure.Availability
                AuthPlatform = $authFailure.Platform
                WindowsAvailability = $windows.Availability
                WindowsPlatform = $windows.Platform
            }
        }

        Assert-Equal -Expected 'Unavailable' -Actual $classification.TimeoutAvailability -Because 'a hard timeout should be skippable'
        Assert-True -Condition $classification.TimeoutReason.Contains('Connection timed out') -Because 'the skip should retain operator evidence'
        Assert-Equal -Expected 'Reachable' -Actual $classification.AuthAvailability -Because 'authentication failures must continue into preflight and fail closed'
        Assert-Equal -Expected 'Unix' -Actual $classification.AuthPlatform -Because 'a failed Windows probe should retain the existing Unix fallback'
        Assert-Equal -Expected 'Reachable' -Actual $classification.WindowsAvailability
        Assert-Equal -Expected 'Windows' -Actual $classification.WindowsPlatform
    }

    Test-Case 'inventory retains unavailable targets while continuing reachable hosts' {
        $probe = & $module {
            $originalConnection = (Get-Item Function:Get-AgentGuidanceTargetConnection).ScriptBlock
            $originalSsh = (Get-Item Function:Invoke-AgentGuidanceSsh).ScriptBlock
            try {
                Set-Item Function:script:Get-AgentGuidanceTargetConnection -Value {
                    param([string] $ComputerName)
                    if ($ComputerName -eq 'offline-host') {
                        return [pscustomobject]@{
                            Availability = 'Unavailable'
                            Platform = $null
                            Failure = 'ssh: connect to host offline-host port 22: Connection timed out'
                        }
                    }
                    [pscustomobject]@{ Availability = 'Reachable'; Platform = 'Unix'; Failure = $null }
                }
                Set-Item Function:script:Invoke-AgentGuidanceSsh -Value {
                    param([string] $ComputerName, [string] $RemoteCommand, [string] $InputText)
                    $output = if ($RemoteCommand -match '\$HOME') { @('/home/tester') } else { @('ok') }
                    [pscustomobject]@{ ExitCode = 0; Output = $output }
                }

                $inventory = @(Get-AgentGuidanceInventory -ComputerName @('offline-host', 'online-host') -File @())
                $preview = @(Show-AgentGuidancePreview -Inventory $inventory -SourceLabel 'test-source' 6>&1) -join "`n"
                [pscustomobject]@{
                    Count = $inventory.Count
                    OfflineAvailability = $inventory[0].Availability
                    OnlineAvailability = $inventory[1].Availability
                    OnlineHome = $inventory[1].RemoteHome
                    Preview = $preview
                }
            }
            finally {
                Set-Item Function:script:Get-AgentGuidanceTargetConnection -Value $originalConnection
                Set-Item Function:script:Invoke-AgentGuidanceSsh -Value $originalSsh
            }
        }

        Assert-Equal -Expected 2 -Actual $probe.Count -Because 'one offline host must not discard the reachable inventory'
        Assert-Equal -Expected 'Unavailable' -Actual $probe.OfflineAvailability
        Assert-Equal -Expected 'Reachable' -Actual $probe.OnlineAvailability
        Assert-Equal -Expected '/home/tester' -Actual $probe.OnlineHome
        Assert-True -Condition $probe.Preview.Contains('unavailable; skipped') -Because 'the operator must see that a target was skipped'
        Assert-True -Condition $probe.Preview.Contains('offline-host') -Because 'the skipped target should be named'
    }

    Test-Case 'authentication failures still stop inventory' {
        $failureMessage = & $module {
            $originalConnection = (Get-Item Function:Get-AgentGuidanceTargetConnection).ScriptBlock
            $originalSsh = (Get-Item Function:Invoke-AgentGuidanceSsh).ScriptBlock
            try {
                Set-Item Function:script:Get-AgentGuidanceTargetConnection -Value {
                    [pscustomobject]@{ Availability = 'Reachable'; Platform = 'Unix'; Failure = $null }
                }
                Set-Item Function:script:Invoke-AgentGuidanceSsh -Value {
                    [pscustomobject]@{
                        ExitCode = 255
                        Output = @('auth-host: Permission denied (publickey).')
                    }
                }

                try {
                    Get-AgentGuidanceInventory -ComputerName @('auth-host') -File @() | Out-Null
                    'NO_ERROR'
                }
                catch {
                    $_.Exception.Message
                }
            }
            finally {
                Set-Item Function:script:Get-AgentGuidanceTargetConnection -Value $originalConnection
                Set-Item Function:script:Invoke-AgentGuidanceSsh -Value $originalSsh
            }
        }

        Assert-True -Condition ($failureMessage -match 'Permission denied') -Because 'authentication failure evidence should stop the run'
        Assert-True -Condition ($failureMessage -ne 'NO_ERROR') -Because 'authentication failures must never be skipped'
    }

    Test-Case 'successful replacement is atomic, backed up, and receipted' {
        $caseRoot = Join-Path $temporaryRoot "successful quote's case"
        $destination = Join-Path $caseRoot 'AGENTS.md'
        $stage = Join-Path $caseRoot '.AGENTS.md.stage'
        Set-TestText -Path $destination -Content 'old guidance'
        Set-TestText -Path $stage -Content 'new guidance'
        $oldHash = Get-TestHash -Path $destination
        $newHash = Get-TestHash -Path $stage
        $suffix = 'success'
        $program = New-LocalCommitProgram -Module $module -DestinationPath $destination -StagePath $stage -ExpectedHash $oldHash -WantedHash $newHash -BackupSuffix $suffix
        $output = @(Invoke-LocalCommitProgram -Program $program)

        Assert-True -Condition ($output[-1] -match '^UPDATED\|test-file\|') -Because 'the commit should emit an UPDATED receipt'
        Assert-Equal -Expected 'new guidance' -Actual ([IO.File]::ReadAllText($destination))
        Assert-Equal -Expected 'old guidance' -Actual ([IO.File]::ReadAllText($destination + '.bak.' + $suffix))
        Assert-True -Condition (-not (Test-Path -LiteralPath $stage)) -Because 'the stage should be consumed by atomic replacement'
        Assert-Equal -Expected $newHash -Actual (Get-TestHash -Path $destination) -Because 'destination readback should match the wanted hash'
    }

    Test-Case 'a stale destination hash fails closed before replacement' {
        $caseRoot = Join-Path $temporaryRoot 'stale-fence'
        $destination = Join-Path $caseRoot 'AGENTS.md'
        $stage = Join-Path $caseRoot '.AGENTS.md.stage'
        Set-TestText -Path $destination -Content 'changed after preview'
        Set-TestText -Path $stage -Content 'new guidance'
        $wantedHash = Get-TestHash -Path $stage
        $program = New-LocalCommitProgram -Module $module -DestinationPath $destination -StagePath $stage -ExpectedHash ('0' * 64) -WantedHash $wantedHash -BackupSuffix 'stale'

        Assert-Throws -Pattern 'REMOTE_CHANGED' -Script {
            Invoke-LocalCommitProgram -Program $program | Out-Null
        }
        Assert-Equal -Expected 'changed after preview' -Actual ([IO.File]::ReadAllText($destination))
        Assert-True -Condition (Test-Path -LiteralPath $stage) -Because 'the rejected stage should not replace the destination'
        Assert-True -Condition (-not (Test-Path -LiteralPath ($destination + '.bak.stale'))) -Because 'no backup should be made before the fence passes'
    }

    Test-Case 'a damaged or partial stage fails closed before replacement' {
        $caseRoot = Join-Path $temporaryRoot 'damaged-stage'
        $destination = Join-Path $caseRoot 'AGENTS.md'
        $stage = Join-Path $caseRoot '.AGENTS.md.stage'
        $wantedReference = Join-Path $caseRoot 'wanted-reference.md'
        Set-TestText -Path $destination -Content 'old guidance'
        Set-TestText -Path $stage -Content 'partial payload'
        Set-TestText -Path $wantedReference -Content 'complete payload'
        $expectedHash = Get-TestHash -Path $destination
        $wantedHash = Get-TestHash -Path $wantedReference
        $program = New-LocalCommitProgram -Module $module -DestinationPath $destination -StagePath $stage -ExpectedHash $expectedHash -WantedHash $wantedHash -BackupSuffix 'damaged'

        Assert-Throws -Pattern 'STAGE_HASH_MISMATCH' -Script {
            Invoke-LocalCommitProgram -Program $program | Out-Null
        }
        Assert-Equal -Expected 'old guidance' -Actual ([IO.File]::ReadAllText($destination))
        Assert-True -Condition (-not (Test-Path -LiteralPath ($destination + '.bak.damaged'))) -Because 'a corrupt stage must not create or replace anything'
    }

    Test-Case 'an unchanged destination removes staging without creating a backup' {
        $caseRoot = Join-Path $temporaryRoot 'unchanged'
        $destination = Join-Path $caseRoot 'AGENTS.md'
        $stage = Join-Path $caseRoot '.AGENTS.md.stage'
        Set-TestText -Path $destination -Content 'same guidance'
        Set-TestText -Path $stage -Content 'same guidance'
        $hash = Get-TestHash -Path $destination
        $program = New-LocalCommitProgram -Module $module -DestinationPath $destination -StagePath $stage -ExpectedHash $hash -WantedHash $hash -BackupSuffix 'unchanged'
        $output = @(Invoke-LocalCommitProgram -Program $program)

        Assert-True -Condition ($output[-1] -match '^UNCHANGED\|test-file\|') -Because 'the commit should emit an UNCHANGED receipt'
        Assert-True -Condition (-not (Test-Path -LiteralPath $stage)) -Because 'an unchanged stage should be cleaned up'
        Assert-True -Condition (-not (Test-Path -LiteralPath ($destination + '.bak.unchanged'))) -Because 'unchanged content should not create a backup'
    }
}
finally {
    Remove-Module AgentGuidanceSync -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host ''
if ($script:failures.Count -gt 0) {
    $script:failures | Format-Table Name, Message -Wrap -AutoSize
    throw "$($script:failures.Count) test(s) failed; $script:passedCount passed."
}

Write-Host "$script:passedCount tests passed." -ForegroundColor Green
