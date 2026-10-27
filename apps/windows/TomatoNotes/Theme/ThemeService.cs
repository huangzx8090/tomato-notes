using System.Windows;
using Microsoft.Win32;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace TomatoNotes.Windows;

/// 统一的外观入口：把设置里的 system / light / dark 翻译成品牌令牌与 Fluent 主题，
/// 并在系统主题变化时自动跟随。取代原先散落在 SettingsWindow 里的手工换刷逻辑。
internal static class ThemeService
{
    private static string appearance = "system";
    private static bool watching;

    public static bool IsDark { get; private set; }
    public static string Appearance => appearance;

    /// 自绘控件（旋钮）以及需要重算派生颜色的窗口订阅此事件。
    public static event Action? Changed;

    public static void Apply(string value)
    {
        appearance = Normalize(value);
        var dark = appearance == "dark" || (appearance == "system" && WindowsTheme.IsDark());
        IsDark = dark;
        if (Application.Current is { } app)
        {
            BrandTokens.Install(app.Resources, dark);
            var theme = dark ? ApplicationTheme.Dark : ApplicationTheme.Light;
            // Fluent 控件模板依赖 WPF-UI 自己的深浅色字典；品牌令牌走 DynamicResource，两者互不干扰。
            try
            {
                ApplicationThemeManager.Apply(theme, WindowBackdropType.None, false);
                // 品牌强调色：直接盖写 Fluent 的资源键，让勾选框 / 开关 /
                // 输入框焦点边框 / 文本选中色都跟着番茄色走，而不是 Windows 系统色。
                BrandTokens.ApplyFluentAccent(app.Resources, dark);
            }
            catch { /* 字典缺失时只影响 Fluent 内建配色，品牌外观仍然完整 */ }
        }
        Changed?.Invoke();
    }

    public static void WatchSystemTheme()
    {
        if (watching) return;
        watching = true;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
    }

    public static void StopWatching()
    {
        if (!watching) return;
        watching = false;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
    }

    /// 便签窗口这类需要即时取色的地方用这个，避免直接摸资源字典。
    public static Brush Token(string key)
        => Application.Current?.TryFindResource(key) as Brush ?? Brushes.Transparent;

    public static string Normalize(string? value)
        => value is "light" or "dark" ? value : "system";

    private static void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (appearance != "system") return;
        var dispatcher = Application.Current?.Dispatcher;
        if (dispatcher is null) return;
        if (dispatcher.CheckAccess()) Apply(appearance);
        else dispatcher.Invoke(() => Apply(appearance));
    }
}
