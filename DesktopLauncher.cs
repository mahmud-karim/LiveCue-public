using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

internal static class DesktopLauncher {
    [STAThread]
    private static void Main() {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(directory, "Start-LiveCueDesktop.ps1");
        if (!File.Exists(script)) { MessageBox.Show("Keep this launcher beside Start-LiveCueDesktop.ps1.", "LiveCue Desktop"); return; }
        try {
            var configuration = InitialSessionState.CreateDefault();
            configuration.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (var runspace = RunspaceFactory.CreateRunspace(configuration)) {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (var shell = PowerShell.Create()) {
                    shell.Runspace = runspace;
                    shell.AddCommand(script).Invoke();
                    if (shell.HadErrors) MessageBox.Show("LiveCue could not finish startup. Run the diagnostic PowerShell launcher for details.", "LiveCue Desktop");
                }
            }
        } catch (Exception error) { MessageBox.Show(error.Message, "LiveCue Desktop"); }
    }
}
