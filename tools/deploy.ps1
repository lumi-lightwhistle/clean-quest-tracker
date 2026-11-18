<#
.SYNOPSIS
  Copies the add-on from this repository into a WoW AddOns folder for testing.

.EXAMPLE
  .\tools\deploy.ps1 -AddOns "D:\World of Warcraft\_forever_\Interface\AddOns"

.NOTES
  Copies only what the game loads: the .toc and the Core, Tracker, UI and Media folders.
  It replaces the CleanQuestTracker folder inside the AddOns folder you name, so point it at a
  test install if you do not want your live copy changed. New or moved files need a full game
  restart; edits only need /reload.
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
foreach ($folder in 'Core', 'Tracker', 'UI', 'Media') {
  Copy-Item (Join-Path $repo $folder) $dest -Recurse
}
Write-Host "Copied to $dest"
