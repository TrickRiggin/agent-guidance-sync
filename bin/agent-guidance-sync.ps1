#!/usr/bin/env pwsh
#Requires -Version 7.2

<#
.SYNOPSIS
Previews or applies agent guidance synchronization from the npm-installed CLI.

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

[CmdletBinding()]
param(
    [string[]] $ComputerName,

    [string] $ConfigPath,

    [switch] $Apply,

    [switch] $Settings,

    [switch] $Init,

    [switch] $NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path $PSScriptRoot '../AgentGuidanceSync/AgentGuidanceSync.psd1'
Import-Module $manifestPath -Force -ErrorAction Stop

Sync-AgentGuidance @PSBoundParameters
