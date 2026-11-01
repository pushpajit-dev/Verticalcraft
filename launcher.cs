using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Windows.Forms;

namespace VerticalCraft
{
    static class Program
    {
        private static Process backendProcess = null;
        private static bool startedBackend = false;

        [STAThread]
        static void Main(string[] args)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string port = "8765";
            string host = "127.0.0.1";
            string url = "http://" + host + ":" + port + "/";

            // Register cleanup on process exit
            AppDomain.CurrentDomain.ProcessExit += (s, e) => CleanupBackend();

            // 1. Check if backend is already listening
            bool isRunning = IsPortOpen(host, int.Parse(port));
            if (!isRunning)
            {
                // Start FastAPI Backend
                string pythonExe = Path.Combine(appDir, ".venv", "Scripts", "python.exe");
                if (!File.Exists(pythonExe))
                {
                    pythonExe = "python.exe";
                }

                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = pythonExe;
                    psi.Arguments = "-m uvicorn backend.main:app --host " + host + " --port " + port;
                    psi.WorkingDirectory = appDir;
                    psi.CreateNoWindow = true;
                    psi.UseShellExecute = false;
                    psi.WindowStyle = ProcessWindowStyle.Hidden;

                    backendProcess = Process.Start(psi);
                    startedBackend = true;
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Failed to launch VerticalCraft AI backend:\n" + ex.Message, "VerticalCraft Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                // Wait for backend to be ready
                bool ready = false;
                for (int i = 0; i < 40; i++)
                {
                    Thread.Sleep(500);
                    if (IsPortOpen(host, int.Parse(port)))
                    {
                        ready = true;
                        break;
                    }
                }

                if (!ready)
                {
                    MessageBox.Show("VerticalCraft backend timed out during startup.", "VerticalCraft Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }

            // 2. Locate browser for standalone Desktop App mode
            string browserPath = FindBrowser();
            string profileDir = Path.Combine(appDir, "projects", ".browser_profile");
            try { Directory.CreateDirectory(profileDir); } catch { }

            Process uiProcess = null;
            if (!string.IsNullOrEmpty(browserPath))
            {
                try
                {
                    ProcessStartInfo bpsi = new ProcessStartInfo();
                    bpsi.FileName = browserPath;
                    bpsi.Arguments = "--app=" + url + " --window-size=1440,920 --user-data-dir=\"" + profileDir + "\"";
                    bpsi.UseShellExecute = false;
                    uiProcess = Process.Start(bpsi);
                }
                catch
                {
                    Process.Start(url);
                }
            }
            else
            {
                Process.Start(url);
            }

            // If we launched a dedicated app window, wait for it to exit then gracefully stop the backend
            if (uiProcess != null)
            {
                try
                {
                    uiProcess.WaitForExit();
                }
                catch { }

                CleanupBackend();
            }
        }

        private static bool IsPortOpen(string host, int port)
        {
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    var result = client.BeginConnect(host, port, null, null);
                    bool success = result.AsyncWaitHandle.WaitOne(500);
                    if (!success) return false;
                    client.EndConnect(result);
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        private static string FindBrowser()
        {
            string[] paths = new string[]
            {
                @"C:\Program Files\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Google\Chrome\Application\chrome.exe"),
                @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                @"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\Edge\Application\msedge.exe")
            };

            foreach (string p in paths)
            {
                if (File.Exists(p)) return p;
            }
            return null;
        }

        private static void CleanupBackend()
        {
            if (startedBackend && backendProcess != null)
            {
                try
                {
                    if (!backendProcess.HasExited)
                    {
                        KillProcessTree(backendProcess.Id);
                    }
                }
                catch { }
                backendProcess = null;
            }
        }

        private static void KillProcessTree(int pid)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("taskkill", "/F /T /PID " + pid);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch { }
        }
    }
}
