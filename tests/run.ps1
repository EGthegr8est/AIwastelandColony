<#
Runs the Godot test suite (or benchmarks). Examples, from anywhere:
    .\tests\run.ps1                                     every test, headless
    .\tests\run.ps1 --filter=render                     tests whose path::name contains "render"
    .\tests\run.ps1 -Windowed --filter=snapshot         tests that need a real GPU (pixel snapshots)
    .\tests\run.ps1 -Windowed --bench --save=before     benchmarks with real GPU numbers, saved as "before"
    .\tests\run.ps1 -Windowed --bench --compare=before  ...and later, compared with that run
Godot is found from $env:GODOT, then Godot_v*_console.exe on the Desktop, then `godot` on PATH.
#>
param([switch]$Windowed, [Parameter(ValueFromRemainingArguments = $true)][string[]]$RunnerArgs)

$godot = $env:GODOT
if (-not $godot) {
    $godot = Get-ChildItem "$HOME\Desktop\Godot_v*\Godot_v*_console.exe", "$HOME\Desktop\Godot_v*_console.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $godot = $cmd.Source }
}
if (-not $godot) {
    Write-Error "Godot not found. Set `$env:GODOT to the path of Godot's _console.exe."
    exit 2
}

$godotArgs = @("--path", (Split-Path $PSScriptRoot), "-s", "res://tests/run_tests.gd")
if (-not $Windowed) { $godotArgs = @("--headless") + $godotArgs }
if ($RunnerArgs) { $godotArgs += @("--") + $RunnerArgs }
& $godot @godotArgs
exit $LASTEXITCODE
