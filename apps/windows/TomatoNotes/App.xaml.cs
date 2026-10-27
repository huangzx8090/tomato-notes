using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Threading;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

public partial class App : System.Windows.Application
{
    private AppState? state;
    private MainWindow? window;
    private TrayService? tray;
    private Mutex? singleInstance;
    private EventWaitHandle? activateSignal;
    private EventWaitHandle? shutdownSignal;
    private CancellationTokenSource? activationLoop;
    private LocalRepository? repository;
    public static string DataPath { get; private set; } = "";
    public static bool IsTest { get; private set; }

    private void Application_Startup(object sender, System.Windows.StartupEventArgs e)
    {
        try
        {
            var custom = e.Args.SkipWhile(x => x != "--data-dir").Skip(1).FirstOrDefault();
            if (e.Args.Contains("--data-dir") && (custom is null || custom.StartsWith("--"))) throw new InvalidOperationException("--data-dir 后需要提供独立资料目录。");
            IsTest = e.Args.Contains("--ui-test");
            var shared = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TomatoNotes");
            DataPath = Path.GetFullPath(custom ?? (IsTest ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TomatoNotes-QA") : shared));
            if (IsTest && string.Equals(DataPath.TrimEnd(Path.DirectorySeparatorChar), shared.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("测试模式不能使用日常资料目录。");
            if (e.Args.Contains("--shared-data") && (IsTest || custom is not null)) throw new InvalidOperationException("--shared-data 不能与 --data-dir 或 --ui-test 同时使用。");
            AppDomain.CurrentDomain.ProcessExit += (_, _) => repository?.Dispose();
            var token = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(DataPath)))[..16];
            singleInstance = new Mutex(true, $"Local\\TomatoNotes-{token}", out var first);
            activateSignal = new EventWaitHandle(false, EventResetMode.AutoReset, $"Local\\TomatoNotes-activate-{token}");
            shutdownSignal = new EventWaitHandle(false, EventResetMode.AutoReset, $"Local\\TomatoNotes-shutdown-{token}");
            if (!first) { (e.Args.Contains("--shutdown") ? shutdownSignal : activateSignal).Set(); singleInstance.Dispose(); return; }
            if (e.Args.Contains("--shutdown")) return;
            activationLoop = new();
            _ = Task.Run(async () => { while (!activationLoop.IsCancellationRequested) { var selected = WaitHandle.WaitAny([activateSignal, shutdownSignal]); if (selected == 1) { await Dispatcher.InvokeAsync(() => window?.ExitApplication()); break; } await Dispatcher.InvokeAsync(() => window?.ShowFromTray()); } }, activationLoop.Token);
            repository = new LocalRepository(DataPath);
            state = new AppState(repository);
            // 先按保存的外观安装品牌令牌，再创建窗口，避免首帧闪一下默认色。
            ThemeService.Apply(state.Data.Settings.Appearance);
            ThemeService.WatchSystemTheme();
            window = new MainWindow(state);
            MainWindow = window;
            tray = new TrayService(window, state);
            window.ShowFromTray();
        }
        catch (Exception ex)
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "tomato-crash.log"), ex.ToString());
            MessageBox.Show(ex.Message + "\n\n应用未打开或修改其他资料。", "番茄小记", MessageBoxButton.OK, MessageBoxImage.Warning);
            singleInstance?.Dispose(); Shutdown();
        }
    }
    private void Application_Exit(object sender, System.Windows.ExitEventArgs e)
    {
        state?.Dispose(); tray?.Dispose(); ThemeService.StopWatching(); activationLoop?.Cancel(); activateSignal?.Dispose(); shutdownSignal?.Dispose(); singleInstance?.Dispose(); repository?.Dispose();
    }
    public void ShowMainWindow() => window?.ShowFromTray();
}
