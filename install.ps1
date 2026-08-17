#Requires -Version 7.2

[CmdletBinding()]
param(
    [string] $ModuleRoot,

    [switch] $DevelopmentLink,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'AgentGuidanceSync'))
$sourceManifest = Join-Path $sourceDirectory 'AgentGuidanceSync.psd1'
if (-not (Test-Path -LiteralPath $sourceManifest -PathType Leaf)) {
    throw "Module manifest is missing: $sourceManifest"
}

if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
    if ($IsWindows) {
        $documentsDirectory = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($documentsDirectory)) {
            throw 'Could not resolve the current user Documents directory. Pass -ModuleRoot explicitly.'
        }
        $ModuleRoot = Join-Path $documentsDirectory 'PowerShell/Modules'
    }
    else {
        $profileRoot = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($profileRoot)) {
            throw 'Could not resolve the current user profile. Pass -ModuleRoot explicitly.'
        }
        $ModuleRoot = Join-Path $profileRoot '.local/share/powershell/Modules'
    }
}

$resolvedModuleRoot = [IO.Path]::GetFullPath($ModuleRoot)
$destination = [IO.Path]::GetFullPath((Join-Path $resolvedModuleRoot 'AgentGuidanceSync'))
if ([IO.Path]::GetDirectoryName($destination) -ne $resolvedModuleRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) {
    throw "Unexpected module destination: $destination"
}
if ($destination -eq $sourceDirectory) {
    throw 'The repository module directory is already the install destination.'
}

Import-Module $sourceManifest -Force -ErrorAction Stop
if (-not (Get-Command Sync-AgentGuidance -Module AgentGuidanceSync -ErrorAction SilentlyContinue)) {
    throw 'The source module imported but did not export Sync-AgentGuidance.'
}
Remove-Module AgentGuidanceSync -Force

New-Item -ItemType Directory -Path $resolvedModuleRoot -Force | Out-Null
$backupPath = $null
if (Test-Path -LiteralPath $destination) {
    if (-not $Force) {
        throw "The module destination already exists: $destination. Re-run with -Force to preserve it as a timestamped backup and replace it."
    }
    $backupPath = $destination + '.bak.' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    if (Test-Path -LiteralPath $backupPath) {
        throw "The planned backup path already exists: $backupPath"
    }
    Move-Item -LiteralPath $destination -Destination $backupPath
}

$stagePath = $destination + '.install-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
try {
    if ($DevelopmentLink) {
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $stagePath -Target $sourceDirectory | Out-Null
    }
    else {
        Copy-Item -LiteralPath $sourceDirectory -Destination $stagePath -Recurse
    }
    Move-Item -LiteralPath $stagePath -Destination $destination
}
catch {
    if (-not (Test-Path -LiteralPath $destination) -and $null -ne $backupPath -and (Test-Path -LiteralPath $backupPath)) {
        Move-Item -LiteralPath $backupPath -Destination $destination
    }
    throw
}

$installedManifest = Join-Path $destination 'AgentGuidanceSync.psd1'
Import-Module $installedManifest -Force -ErrorAction Stop
$command = Get-Command Sync-AgentGuidance -Module AgentGuidanceSync -ErrorAction Stop

Write-Host "Installed AgentGuidanceSync at $destination" -ForegroundColor Green
Write-Host "Mode: $(if ($DevelopmentLink) { 'development link' } else { 'copy' })"
if ($null -ne $backupPath) {
    Write-Host "Previous installation preserved at $backupPath" -ForegroundColor Yellow
}
Write-Host "Command: $($command.Name)  (alias: ag-sync)"
Write-Host "Create a starter config: ag-sync -init"
