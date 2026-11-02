# Run app and Restart Manager probe on the interactive desktop with real tokens:
# LIMITED = the user's ordinary (medium IL) token, HIGHEST = elevated. No restricted tokens.
$exe = "$env:TEMP\rm-race\RmRaceApp.exe"
$home_ = $env:USERPROFILE
function Task([string]$name, [string]$cmd, [string]$level) {
    schtasks /Create /F /TN $name /TR $cmd /SC ONCE /ST 00:00 /RL $level /IT | Out-Null
    schtasks /Run /TN $name | Out-Null
}
function Scenario([string]$label, [string]$appLevel, [string]$rmLevel, [string]$appArgs, [int]$rmDelayMs) {
    Get-Process RmRaceApp -ErrorAction SilentlyContinue | Stop-Process -Force
    $out = "$home_\desk-$label.txt"; Remove-Item $out -ErrorAction SilentlyContinue
    Task 'rmrace-app' "`"$exe`" $appArgs" $appLevel
    $deadline = (Get-Date).AddSeconds(5); $app = $null
    while (-not $app -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; $app = Get-Process RmRaceApp -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $app) { "$label : app did not start"; return }
    $started = Get-Date
    $il = (whoami /all) -match 'Mandatory Label' | Out-Null
    Start-Sleep -Milliseconds $rmDelayMs
    Task 'rmrace-rm' "cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File $home_\rm-race.ps1 -ExistingPid $($app.Id) > $out 2>&1" $rmLevel
    $deadline = (Get-Date).AddSeconds(40)
    while (-not (Test-Path $out) -or (Get-Content $out -ErrorAction SilentlyContinue | Measure-Object -Line).Lines -lt 2) { if ((Get-Date) -gt $deadline) { break }; Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds 500
    "## $label (app=$appLevel rm=$rmLevel args='$appArgs' rm-after=${rmDelayMs}ms)"
    Get-Content $out -ErrorAction SilentlyContinue | Select-Object -Last 2
    Get-Process RmRaceApp -ErrorAction SilentlyContinue | Stop-Process -Force
}
Scenario 'user-user'            LIMITED LIMITED '' 500
Scenario 'user-user-teardown'   LIMITED LIMITED '--exit-after 1500 --teardown 4000' 2000
Scenario 'elevated-user'        HIGHEST LIMITED '' 500
Scenario 'elevated-elevated'    HIGHEST HIGHEST '' 500
Scenario 'user-elevated'        LIMITED HIGHEST '' 500
schtasks /Delete /F /TN rmrace-app | Out-Null; schtasks /Delete /F /TN rmrace-rm | Out-Null
