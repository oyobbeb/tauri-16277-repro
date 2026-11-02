// A Win32 GUI app whose exit can be made slow, to see what Restart Manager makes of an app
// that is already on its way out (tauri-apps/tauri#16277).
//   RmRaceApp.exe                         stays open until closed (WM_CLOSE / WM_ENDSESSION)
//   RmRaceApp.exe --exit-after 300 --teardown 3000
//                                         closes its window after 300 ms, then keeps the process
//                                         alive for 3000 ms more before exiting, like an app
//                                         shutting down its webview after launching an installer
using System;
using System.Threading;
using System.Windows.Forms;

static class Program {
    [STAThread]
    static void Main(string[] args) {
        int exitAfter = 0, teardown = 0;
        for (int i = 0; i + 1 < args.Length; i++) {
            if (args[i] == "--exit-after") exitAfter = int.Parse(args[i + 1]);
            if (args[i] == "--teardown") teardown = int.Parse(args[i + 1]);
        }
        var form = new Form { Text = "RmRaceApp", Width = 300, Height = 120, ShowInTaskbar = true };
        if (exitAfter > 0) {
            var timer = new System.Windows.Forms.Timer { Interval = exitAfter };
            timer.Tick += (s, e) => { timer.Stop(); form.Close(); };
            timer.Start();
        }
        Application.Run(form);
        // The window is gone, the process is not: this is the window the installer races.
        if (teardown > 0) Thread.Sleep(teardown);
    }
}
