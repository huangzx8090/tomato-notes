using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using TomatoNotes.Core;
using Forms = System.Windows.Forms;

namespace TomatoNotes.Windows;

public static class CredentialStore
{
    private static string Root => Path.Combine(App.DataPath, "Credentials");
    private static string PathFor(string provider) => Path.Combine(Root, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(provider))) + ".key");
    public static string? Read(string provider)
    {
        var names = new[] { "AI_API_KEY", provider.ToUpperInvariant().Replace('-', '_') + "_API_KEY" };
        if (provider == "deepseek") names = names.Concat(["deepseek", "DEEPSEEK_API_KEY"]).ToArray();
        foreach (var name in names) { var key = Environment.GetEnvironmentVariable(name)?.Trim(); if (!string.IsNullOrEmpty(key)) return key; }
        var path = PathFor(provider); if (!File.Exists(path)) return null;
        try { return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(path), Encoding.UTF8.GetBytes("TomatoNotes:" + provider), DataProtectionScope.CurrentUser)); }
        catch (CryptographicException) { throw new InvalidOperationException("无法解密本机 API Key，请重新保存。"); }
    }
    public static void Save(string provider, string value) { Directory.CreateDirectory(Root); File.WriteAllBytes(PathFor(provider), ProtectedData.Protect(Encoding.UTF8.GetBytes(value.Trim()), Encoding.UTF8.GetBytes("TomatoNotes:" + provider), DataProtectionScope.CurrentUser)); }
    public static void Remove(string provider) { var path = PathFor(provider); if (File.Exists(path)) File.Delete(path); }
    public static bool IsConfigured(string provider) { try { return Read(provider) is not null; } catch { return false; } }
}

public sealed class ForegroundAppService
{
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    public AppIdentity? Current()
    {
        var window = GetForegroundWindow(); if (window == IntPtr.Zero) return null;
        GetWindowThreadProcessId(window, out var pid); if (pid == 0 || pid == Environment.ProcessId) return null;
        try { var process = Process.GetProcessById((int)pid); return new(process.ProcessName, process.ProcessName + ".exe"); } catch { return null; }
    }
}

public sealed class TrayService : IDisposable
{
    private readonly Forms.NotifyIcon icon;
    private readonly MainWindow window;
    public TrayService(MainWindow window, AppState state)
    {
        this.window = window;
        icon = new() { Icon = new Icon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico")), Text = "番茄小记", Visible = true, ContextMenuStrip = new() };
        icon.ContextMenuStrip.Items.Add("打开番茄小记", null, (_, _) => window.ShowFromTray());
        icon.ContextMenuStrip.Items.Add("快速待办", null, (_, _) => window.ShowQuickTodo());
        icon.ContextMenuStrip.Items.Add("新建便签", null, (_, _) => window.CreateNote());
        icon.ContextMenuStrip.Items.Add(new Forms.ToolStripSeparator());
        icon.ContextMenuStrip.Items.Add("退出（计时会暂停并保存）", null, (_, _) => window.ExitApplication());
        icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) window.ShowFromTray(); };
        state.NotificationRequested += Send;
    }
    public void Send(string title, string body, bool sound, bool notification)
    {
        if (sound) System.Media.SystemSounds.Asterisk.Play();
        if (notification) icon.ShowBalloonTip(6000, title, body, Forms.ToolTipIcon.Info);
    }
    public void Dispose() { icon.Visible = false; icon.Dispose(); }
}

public sealed class GlobalHotkeyService : IDisposable
{
    private readonly HwndSource source;
    private readonly Dictionary<int, Action> actions = [];
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    public GlobalHotkeyService(Window window) { var handle = new WindowInteropHelper(window).EnsureHandle(); source = handle != IntPtr.Zero ? HwndSource.FromHwnd(handle)! : throw new InvalidOperationException("无法注册快捷键"); source.AddHook(WndProc); }
    public string? Register(int id, Hotkey hotkey, Action action)
    {
        Unregister(id); if (!hotkey.Enabled) return null;
        var key = hotkey.Letter.Trim().ToUpperInvariant(); if (key.Length != 1 || key[0] is < 'A' or > 'Z') return "快捷键目前支持单个英文字母。";
        // macOS Control+Option maps naturally to Windows Ctrl+Alt.
        if (!RegisterHotKey(source.Handle, id, 0x0002 | 0x0001 | 0x4000, key[0])) return $"Ctrl + Alt + {key} 已被其他程序占用。";
        actions[id] = action; return null;
    }
    public void Unregister(int id) { if (source.Handle != IntPtr.Zero) UnregisterHotKey(source.Handle, id); actions.Remove(id); }
    private IntPtr WndProc(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled) { if (message == 0x0312 && actions.TryGetValue(wparam.ToInt32(), out var action)) { action(); handled = true; } return IntPtr.Zero; }
    public void Dispose() { foreach (var id in actions.Keys.ToList()) Unregister(id); source.RemoveHook(WndProc); }
}

public static class WorkImageStore
{
    public static void Import(IEnumerable<string> files, WorkRecord record, string root)
    {
        Directory.CreateDirectory(root);
        foreach (var file in files)
        {
            if (new FileInfo(file).Length > 25 * 1024 * 1024) throw new InvalidDataException($"{Path.GetFileName(file)} 超过 25 MB。");
            BitmapDecoder decoder;
            using (var stream = File.OpenRead(file)) decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var source = decoder.Frames[0]; var scale = Math.Min(1, 1600d / Math.Max(source.PixelWidth, source.PixelHeight));
            var transformed = new TransformedBitmap(source, new System.Windows.Media.ScaleTransform(scale, scale));
            var image = new WorkImage { Name = Path.GetFileName(file) }; var encoder = new JpegBitmapEncoder { QualityLevel = 88 }; encoder.Frames.Add(BitmapFrame.Create(transformed));
            using var output = File.Create(Path.Combine(root, image.FileName)); encoder.Save(output); record.Images.Add(image);
        }
    }
}
