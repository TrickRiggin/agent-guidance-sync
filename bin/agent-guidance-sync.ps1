#!/usr/bin/env pwsh
#Requires -Version 7.2

<#
.SYNOPSIS
Previews or applies agent guidance synchronization from the npm-installed CLI.

.EXAMPLE
agent-guidance-sync

.EXAMPLE
agent-guidance-sync -Apply

.EXAMPLE
agent-guidance-sync -ComputerName host-one -Apply
#>

[CmdletBinding()]
param(
    [string[]] $ComputerName,

    [string] $ConfigPath,

    [switch] $Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot '../AgentGuidanceSync/AgentGuidanceSync.psd1'
Import-Module $manifestPath -Force -ErrorAction Stop

Sync-AgentGuidance @PSBoundParameters
