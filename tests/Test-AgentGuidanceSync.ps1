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
        Assert-Equal -Expected '0.3.0' -Actual $manifest.Version.ToString() -Because 'semantic Codex config projection should ship as version 0.3.0'
        $exportedCommands = @((Get-Command -Module AgentGuidanceSync).Name | Sort-Object -Unique)
        Assert-Equal -Expected 1 -Actual $exportedCommands.Count -Because 'only one command should be public'
        Assert-Equal -Expected 'Sync-AgentGuidance' -Actual $exportedCommands[0] -Because 'the sync command should be exported'
        $applyParameter = (Get-Command Sync-AgentGuidance).Parameters['Apply']
        Assert-Equal -Expected ([switch].FullName) -Actual $applyParameter.ParameterType.FullName -Because 'remote writes should require an explicit switch'
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
    }

    Test-Case 'shipped starter and multi-harness configs remain valid and narrowly scoped' {
        $starterPath = Join-Path $repositoryRoot 'config.example.json'
        $starter = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $starterPath
        Assert-Equal -Expected 2 -Actual $starter.Files.Count -Because 'the starter should stay focused on Codex and Claude'

        $multiHarnessPath = Join-Path $repositoryRoot 'config.multi-harness.example.json'
        $multiHarness = & $module { param($path) Import-AgentGuidanceConfig -ConfigPath $path } $multiHarnessPath
        Assert-Equal -Expected 5 -Actual $multiHarness.Files.Count -Because 'the broader preset should cover five verified harnesses'

        $expectedDestinations = @(
            '.codex/AGENTS.md',
            '.claude/CLAUDE.md',
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
