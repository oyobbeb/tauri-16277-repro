# tauri#16277: "Failed to kill" reproduction

Calls the same Restart Manager sequence as Tauri's NSIS template (`RmStartSession` → `RmRegisterResources` → `RmGetList` → `RmShutdown(RmForceShutdown)`) against a small WinForms app, with real elevated and unelevated tokens on the interactive desktop.

## Files

- `RmRaceApp.cs` — the app. `--exit-after <ms> --teardown <ms>` closes the window and keeps the process alive for a while, like an app shutting down after launching its installer.
- `build-app.ps1` — compiles it with the .NET Framework `csc.exe` into `%TEMP%\rm-race\RmRaceApp.exe`.
- `rm-race.ps1` — the probe. Without arguments it runs the timing scenarios on its own app; `-ExistingPid <pid>` probes an app started elsewhere.
- `desk.ps1` — runs app and probe through scheduled tasks (`/RL LIMITED` = the user's ordinary token, `/RL HIGHEST` = elevated), so the tokens are the real ones, not `runas /trustlevel` restricted tokens.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File build-app.ps1
powershell -ExecutionPolicy Bypass -File desk.ps1     # from an elevated prompt; creates and removes the tasks
```

## Results (Windows 11 build 26200)

| app      | RM caller | state                                   | RmGetList                 | RmShutdown |
|----------|-----------|-----------------------------------------|---------------------------|------------|
| user     | user      | window open                             | 1 process, reasons 0      | 0          |
| user     | user      | window closed, 4 s teardown in progress | 1 process, reasons 0      | 0 after 2.1 s |
| elevated | user      | window open                             | 1 process, **reasons 1** (`RmRebootReasonPermissionDenied`) | **350** (`ERROR_FAIL_SHUTDOWN`) |
| elevated | elevated  | window open                             | 1 process, reasons 0      | 0          |
| user     | elevated  | window open                             | 1 process, reasons 0      | 0          |

With a stock `create-tauri-app` app (`currentUser` NSIS installer): start the app elevated, run the installer in passive mode → "Failed to kill rmrace-tauri. Please close it first then try again".
