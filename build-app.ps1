$csc = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$out = "$env:TEMP\rm-race\RmRaceApp.exe"
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
& $csc /nologo /target:winexe /out:$out /r:System.Windows.Forms.dll "$env:USERPROFILE\RmRaceApp.cs"
"built=$(Test-Path $out) size=$((Get-Item $out).Length)"
