using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

/// 守护用到的前台窗口信息。句柄与进程号属于系统层，不进入 Core 的规则计算。
public sealed record GuardForeground(IntPtr Handle, int ProcessID, string AppID, string AppName, string WindowTitle);

public sealed class GuardForegroundService
{
    private readonly Dictionary<int, string> displayNames = [];

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);

    public GuardForeground? Current()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return null;
        GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0 || pid == Environment.ProcessId) return null;
        string processName;
        try { using var process = Process.GetProcessById((int)pid); processName = process.ProcessName; }
        catch (ArgumentException) { return null; }
        return new(hwnd, (int)pid, processName + ".exe", DisplayName((int)pid, processName), Title(hwnd));
    }

    /// 关闭前必须确认目标仍是前台窗口，否则会动到用户刚切过去的内容。
    public bool IsForeground(IntPtr hwnd) => hwnd != IntPtr.Zero && GetForegroundWindow() == hwnd;

    public string Title(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return "";
        var builder = new StringBuilder(1024);
        return GetWindowText(hwnd, builder, builder.Capacity) == 0 ? "" : builder.ToString();
    }

    public string? ImagePath(int pid)
    {
        try { using var process = Process.GetProcessById(pid); return process.MainModule?.FileName; }
        catch (Win32Exception) { return null; }
        catch (InvalidOperationException) { return null; }
        catch (NotSupportedException) { return null; }
        catch (ArgumentException) { return null; }
    }

    /// 用可执行文件里的产品描述做展示名，读不到就退回进程名；按进程号缓存，避免每个心跳都读文件。
    private string DisplayName(int pid, string processName)
    {
        if (displayNames.TryGetValue(pid, out var cached)) return cached;
        if (displayNames.Count > 256) displayNames.Clear();
        var name = processName;
        try
        {
            using var process = Process.GetProcessById(pid);
            var description = process.MainModule?.FileVersionInfo.FileDescription;
            if (!string.IsNullOrWhiteSpace(description)) name = description.Trim();
        }
        catch (Win32Exception) { }
        catch (InvalidOperationException) { }
        catch (NotSupportedException) { }
        catch (ArgumentException) { }
        displayNames[pid] = name;
        return name;
    }
}

/// 用 UI Automation 读浏览器地址栏。实测 Chromium 的地址栏是 Edit 控件，
/// ValuePattern 能拿到含路径与查询条件的完整网址；AutomationId 是随窗口变化的数字，不能用来定位。
public sealed class BrowserPageReader
{
    private static readonly string[] AddressBarNames =
    [
        "地址和搜索栏", "地址栏", "address and search bar", "address bar", "urlbar",
        "搜索或输入网址", "搜索或输入网络地址", "search or enter web address", "search or enter address",
    ];

    private IntPtr handle;
    private string title = "";
    private string? url;
    private DateTime readAt = DateTime.MinValue;

    public string? Read(IntPtr hwnd, string windowTitle)
    {
        // 窗口标题没变就复用上次结果：一次 UIA 树遍历约 100ms，不适合每个心跳都重读。
        if (hwnd == handle && windowTitle == title && DateTime.UtcNow - readAt < TimeSpan.FromSeconds(2)) return url;
        handle = hwnd; title = windowTitle; readAt = DateTime.UtcNow;
        url = ReadAddressBar(hwnd);
        return url;
    }

    public void Invalidate() { handle = IntPtr.Zero; title = ""; url = null; readAt = DateTime.MinValue; }

    private static string? ReadAddressBar(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            if (root is null) return null;
            var edits = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit));
            string? fallback = null;
            for (var i = 0; i < edits.Count; i++)
            {
                var value = ReadValue(edits[i]);
                if (value is null) continue;
                var normalised = Normalize(value);
                if (normalised is null) continue;
                // 先认名字像地址栏的控件，避免把网页里的输入框当成网址。
                if (AddressBarNames.Any(x => Name(edits[i]).Contains(x, StringComparison.OrdinalIgnoreCase))) return normalised;
                fallback ??= normalised;
            }
            return fallback;
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or COMException or InvalidOperationException or ArgumentException or NullReferenceException) { return null; }
    }

    private static string? ReadValue(AutomationElement element)
    {
        try { return element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern) ? ((ValuePattern)pattern).Current.Value : null; }
        catch (Exception ex) when (ex is ElementNotAvailableException or COMException or InvalidOperationException) { return null; }
    }

    private static string Name(AutomationElement element)
    {
        try { return element.Current.Name ?? ""; }
        catch (Exception ex) when (ex is ElementNotAvailableException or COMException or InvalidOperationException) { return ""; }
    }

    /// Chromium 未聚焦时会省略协议头，补全后再交给 pageKey 归一化；含空格说明是搜索词而不是网址。
    private static string? Normalize(string value)
    {
        var text = value.Trim();
        if (text.Length == 0 || text.Contains(' ') || !text.Contains('.')) return null;
        var probe = text.Contains("://") ? text : "https://" + text;
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var url)) return null;
        if (url.Scheme is not ("http" or "https") || !url.Host.Contains('.')) return null;
        return FocusPageRule.PageKey(probe);
    }
}

/// 窗口标题形如「网页标题 - 配置文件 - Microsoft Edge」，取第一段作为网页标题。
public static class BrowserWindowTitle
{
    public static string PageTitle(string windowTitle)
    {
        var text = (windowTitle ?? "").Trim();
        if (text.Length == 0) return "";
        var index = text.IndexOf(" - ", StringComparison.Ordinal);
        return (index > 0 ? text[..index] : text).Trim();
    }
}

/// 关闭动作。始终先给应用留下保存机会：浏览器只关当前标签，其他进程发 WM_CLOSE；
/// 只有用户在本轮单独授权强制结束时才真正终止进程。
public sealed class GuardCloser
{
    private const uint InputKeyboard = 1;
    private const byte VkControl = 0x11;
    private const byte VkW = 0x57;
    private const uint KeyEventUp = 0x0002;
    private const uint WmClose = 0x0010;

    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] private static extern IntPtr PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);

    [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT { public int Dx; public int Dy; public uint MouseData; public uint Flags; public uint Time; public IntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct KEYBDINPUT { public ushort Vk; public ushort Scan; public uint Flags; public uint Time; public IntPtr ExtraInfo; }
    // 联合体的尺寸由最大的成员决定；少了鼠标成员会让 INPUT 结构体大小不对，SendInput 直接失败。
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public MOUSEINPUT Mouse; [FieldOffset(0)] public KEYBDINPUT Key; }
    [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint Type; public InputUnion U; }

    /// 关闭浏览器当前标签。只在目标仍是前台窗口时发送，避免把按键打进别的程序。
    public bool CloseBrowserTab(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        var inputs = new[] { Key(VkControl, 0), Key(VkW, 0), Key(VkW, KeyEventUp), Key(VkControl, KeyEventUp) };
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) == inputs.Length;
    }

    /// 正常关闭：让应用自己处理未保存内容，需要时它会弹出保存提示。
    public bool CloseWindow(IntPtr hwnd) => hwnd != IntPtr.Zero && IsWindow(hwnd) && PostMessage(hwnd, WmClose, IntPtr.Zero, IntPtr.Zero) != IntPtr.Zero;

    public bool ForceClose(int pid)
    {
        if (pid == Environment.ProcessId) return false;
        try
        {
            using var process = Process.GetProcessById(pid);
            process.Kill();
            return process.WaitForExit(5000);
        }
        catch (ArgumentException) { return true; }
        catch (InvalidOperationException) { return true; }
        catch (Win32Exception) { return false; }
        catch (NotSupportedException) { return false; }
    }

    public bool IsRunning(int pid)
    {
        try { using var process = Process.GetProcessById(pid); return !process.HasExited; }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    private static INPUT Key(byte vk, uint flags) => new() { Type = InputKeyboard, U = new InputUnion { Key = new KEYBDINPUT { Vk = vk, Scan = 0, Flags = flags, Time = 0, ExtraInfo = IntPtr.Zero } } };
}
