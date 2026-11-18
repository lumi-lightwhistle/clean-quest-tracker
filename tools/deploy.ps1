<#
.SYNOPSIS
  Copies the add-on from this repository into a WoW AddOns folder for testing.

.EXAMPLE
  .\tools\deploy.ps1 -AddOns "D:\World of Warcraft\_forever_\Interface\AddOns"

.NOTES
  Copies only the files the game loads (the .toc, the .lua files and Media). It replaces
  the CleanQuestTracker folder inside the AddOns folder you name, so point it at a test
  install if you do not want your live copy changed. New files need a full game restart;
  edits only need /reload.
#>
param(
  [Parameter(Mandatory = $true)][string]$AddOns
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $AddOns 'CleanQuestTracker'

if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns" }

New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem $dest -Force | Remove-Item -Recurse -Force
Copy-Item (Join-Path $repo 'CleanQuestTracker.toc') $dest
Copy-Item (Join-Path $repo '*.lua') $dest
Copy-Item (Join-Path $repo 'Media') $dest -Recurse
Write-Host "Copied to $dest"
