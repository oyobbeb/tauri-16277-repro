# Restart Manager exit race probe (tauri-apps/tauri#16277).
# Mirrors the NSIS template: RmStartSession -> RmRegisterResources(exe) -> RmGetList -> RmShutdown(force).
# Varies when the app exits relative to the calls, and records every return code.
param([string]$Work = "$env:TEMP\rm-race", [int]$ExistingPid = 0)

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Rm {
    [StructLayout(LayoutKind.Sequential)] public struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct RM_PROCESS_INFO {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
        public int ApplicationType; public uint AppStatus; public uint TSSessionId; [MarshalAs(UnmanagedType.Bool)] public bool bRestartable; }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] public static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
    [DllImport("rstrtmgr.dll")] public static extern int RmEndSession(uint pSessionHandle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] public static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, IntPtr rgApplications, uint nServices, IntPtr rgsServiceNames);
    [DllImport("rstrtmgr.dll")] public static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
    [DllImport("rstrtmgr.dll")] public static extern int RmShutdown(uint pSessionHandle, uint lActionFlags, IntPtr fnStatus);
    public static void KillAfter(int pid, int ms) { new System.Threading.Thread(() => { System.Threading.Thread.Sleep(ms); try { System.Diagnostics.Process.GetProcessById(pid).Kill(); } catch {} }).Start(); }
}
"@

function Get-List([uint32]$s) {
    $needed = [uint32]0; $n = [uint32]0; $reasons = [uint32]0
    $rc = [Rm]::RmGetList($s, [ref]$needed, [ref]$n, $null, [ref]$reasons)   # 0 = nobody, 234 = ERROR_MORE_DATA
    $status = ''
    if ($rc -eq 234) { $n = $needed; $apps = New-Object Rm+RM_PROCESS_INFO[] $n; $rc2 = [Rm]::RmGetList($s, [ref]$needed, [ref]$n, $apps, [ref]$reasons); $status = ($apps | ForEach-Object { "pid=$($_.Process.dwProcessId):status=$($_.AppStatus)" }) -join ',' }
    "rc=$rc n=$needed reasons=$reasons $status"
}

New-Item -ItemType Directory -Force $Work | Out-Null
$exe = Join-Path $Work 'RmRaceApp.exe'
if (-not (Test-Path $exe)) { throw "build the app first: build-app.ps1" }

function Start-App([string]$appArgs = '') {
    if ($ExistingPid) { return (Get-Process -Id $ExistingPid) }
    if ($appArgs) { Start-Process -FilePath $exe -ArgumentList $appArgs -PassThru } else { Start-Process -FilePath $exe -PassThru }
}

function Probe([string]$name, [scriptblock]$between, [string]$appArgs = '', [int]$settleMs = 500) {
    $p = Start-App $appArgs
    Start-Sleep -Milliseconds $settleMs
    $key = [guid]::NewGuid().ToString('N')
    $s = [uint32]0
    $rc = [Rm]::RmStartSession([ref]$s, 0, $key); if ($rc -ne 0) { throw "RmStartSession=$rc" }
    try {
        $rc = [Rm]::RmRegisterResources($s, 1, [string[]]@($exe), 0, [IntPtr]::Zero, 0, [IntPtr]::Zero); if ($rc -ne 0) { throw "RmRegisterResources=$rc" }
        $before = Get-List $s
        & $between $p
        $exitedBefore = $p.HasExited; $windowGone = ($p.MainWindowHandle -eq 0)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $shutdown = [Rm]::RmShutdown($s, 1, [IntPtr]::Zero)   # 1 = RmForceShutdown
        $sw.Stop()
        $after = Get-List $s
        "{0,-44} before[{1}] exited={2} window-gone={3} RmShutdown={4} ({5} ms) after[{6}] exited-after={7}" -f $name, $before, $exitedBefore, $windowGone, $shutdown, $sw.ElapsedMilliseconds, $after, $p.HasExited
    } finally { [Rm]::RmEndSession($s) | Out-Null; if (-not $ExistingPid -and -not $p.HasExited) { $p.Kill() } }
}

"host: $([Environment]::OSVersion.VersionString) elevated=$((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole('Administrators')) user=$env:USERNAME"
if ($ExistingPid) {
    Probe 'existing app (started elsewhere)' { param($p) }
    exit
}
Probe 'GUI app open (control)'                  { param($p) }
Probe 'GUI app killed, fully gone'              { param($p) $p.Kill(); $p.WaitForExit(); Start-Sleep -Milliseconds 200 }
Probe 'GUI app killed, no wait'                 { param($p) $p.Kill() }
Probe 'GUI app killed during shutdown (+2 ms)'  { param($p) [Rm]::KillAfter($p.Id, 2) }
Probe 'window closed, process tearing down 3 s' { param($p) } '--exit-after 300 --teardown 3000' 800
Probe 'window closed, teardown ends in ~100 ms' { param($p) } '--exit-after 300 --teardown 1000' 1400
Probe 'app replaced by a new pid'               { param($p) $p.Kill(); $p.WaitForExit(); $script:p2 = Start-App; Start-Sleep -Milliseconds 500 }
if ($script:p2 -and -not $script:p2.HasExited) { $script:p2.Kill() }
