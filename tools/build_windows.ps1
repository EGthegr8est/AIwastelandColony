<#
Builds the Windows version of the game and zips it, ready to send to a friend.
    .\tools\build_windows.ps1                        build, check and zip
    .\tools\build_windows.ps1 -Out D:\Somewhere      put the results somewhere else

Needs Godot's Windows export templates (Godot > Editor > Manage Export Templates, or see the README).
The folder it makes, and the zip next to it, go in ..\WastelandColony-release by default:
    WastelandColony\WastelandColony.exe     the game, as a single file (the art and music are inside it)
    WastelandColony\PLAY_ME.txt             how to run it, for your friend
    WastelandColony-Windows.zip             the two above, zipped: send this
It also runs the game's own self-check on the finished build (art, music and data all there), and stops if it fails.
Godot is found like tests\run.ps1 does: $env:GODOT, then Godot_v*_console.exe on your Desktop, then `godot` on PATH.
#>
param([string]$Out = (Join-Path (Split-Path $PSScriptRoot) "..\WastelandColony-release"))

# Godot prints harmless warnings on stderr, which PowerShell would treat as fatal errors: judge by exit codes instead
$ErrorActionPreference = "Continue"
$project = Split-Path $PSScriptRoot
$Out = [System.IO.Path]::GetFullPath($Out)

$godot = $env:GODOT
if (-not $godot) {
    $godot = Get-ChildItem "$HOME\Desktop\Godot_v*\Godot_v*_console.exe", "$HOME\Desktop\Godot_v*_console.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $godot = $cmd.Source }
}
if (-not $godot) { Write-Error "Godot not found. Set `$env:GODOT to the path of Godot's _console.exe."; exit 2 }

$version = (& $godot --version).Trim()              # like 4.7.2.stable.official.ed1daf0bf
$short = ($version -split "\.")[0..3] -join "."      # 4.7.2.stable
$template = "$env:APPDATA\Godot\export_templates\$short\windows_release_x86_64.exe"
if (-not (Test-Path $template)) {
    Write-Error "The Windows export templates for Godot $short aren't installed (looked for $template).`nIn the Godot editor: Editor > Manage Export Templates > Download and Install."
    exit 2
}

$game = Join-Path $Out "WastelandColony"
if (Test-Path $game) { Remove-Item $game -Recurse -Force }
New-Item -ItemType Directory -Force $game | Out-Null

Write-Host "Importing..."
& $godot --headless --path $project --import | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Godot couldn't import the project."; exit 1 }
Write-Host "Exporting to $game ..."
& $godot --headless --path $project --export-release "Windows Desktop" (Join-Path $game "WastelandColony.exe") 2>&1 | Out-Host
if (-not (Test-Path (Join-Path $game "WastelandColony.exe"))) { Write-Error "The export didn't make an .exe: see the messages above."; exit 1 }

Write-Host "Checking the build..."
$check = Get-ChildItem $game -Filter "*.console.exe" | Select-Object -First 1
if (-not $check) { $check = Get-Item (Join-Path $game "WastelandColony.exe") }
& $check.FullName -- --selftest | Tee-Object -Variable lines | Out-Host
if ($LASTEXITCODE -ne 0) { Write-Error "The built game failed its self-check (see the FAIL lines above). Not zipping it."; exit 1 }

# The console wrapper was only for the check; your friend doesn't need it
Get-ChildItem $game -Filter "*.console.exe" | Remove-Item -Force
Copy-Item (Join-Path $PSScriptRoot "PLAY_ME.txt") $game

$zip = Join-Path $Out "WastelandColony-Windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $game -DestinationPath $zip
$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Done: $zip ($mb MB). Send that file."
