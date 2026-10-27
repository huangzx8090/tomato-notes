using System.Windows.Media;

namespace TomatoNotes.Windows;

/// 番茄小记的品牌色令牌，取值与 macOS 的 Sources/TomatoNotes/Theme.swift 一一对应，
/// 保证双端在同一外观下颜色一致。只保留 Windows 端实际会用到的令牌：
/// macOS 的玻璃材质（glass）相关取值在 Windows 上没有对应实现，不在此处伪造。
internal static class BrandTokens
{
    private static readonly (string Key, uint Light, uint Dark)[] Palette =
    [
        ("Background", 0xF6F2EA, 0x211E1B),
        ("Surface", 0xFFFCF6, 0x2D2824),
        ("Ink", 0x302E2B, 0xF0E6D6),
        ("Secondary", 0x706960, 0xBCAD9D),
        ("Accent", 0xA84632, 0xEEA48B),
        ("AccentFill", 0xA84632, 0x98402D),
        ("AccentSoft", 0xF1DDD4, 0x4A3028),
        ("Green", 0x52705D, 0xABC7AC),
        ("GreenFill", 0x52705D, 0x405D47),
        ("GreenSoft", 0xE8EEE6, 0x2E3C30),
        ("Border", 0xE3DBCF, 0x554A40),
        ("TodoPaperTop", 0xFFFDFA, 0x37312B),
        ("TodoPaperBottom", 0xF6EFDF, 0x2E2923),
        ("PaperHighlight", 0xFFFFFF, 0x65584A),
        ("PaperShadow", 0x9C8568, 0x000000),
        ("NotePaper", 0xFBF1D3, 0x342E22),
        ("NoteInk", 0x302E2B, 0xF2E5C3),
        ("NoteAction", 0x7A4D2E, 0xDBC395),
        ("DialRimLight", 0xFFFFFF, 0x65594D),
        ("DialRimShadow", 0xD7D0C5, 0x302A25),
        ("DialRimEnd", 0xF9F5ED, 0x4A4037),
        ("DialFaceLight", 0xFFFEFA, 0x50453A),
        ("DialFaceShadow", 0xEEE7DB, 0x342D26),
        ("DialHighlight", 0xFFFFFF, 0x887661),
        ("DialShadow", 0xB1A391, 0x000000),
    ];

    /// macOS 的 noteRule 带 0.7 透明度，单独处理。
    private const uint NoteRuleLight = 0xD8CAA8;
    private const uint NoteRuleDark = 0x75633F;

    /// 「长休息间隔」旋钮在 macOS 上用的是固定色，不随外观变化。
    internal const uint DialNeutral = 0x9A7D54;

    public static Color FromHex(uint value, byte alpha = 255)
        => Color.FromArgb(alpha, (byte)(value >> 16 & 0xff), (byte)(value >> 8 & 0xff), (byte)(value & 0xff));

    public static Brush Brush(uint value, byte alpha = 255)
    {
        var brush = new SolidColorBrush(FromHex(value, alpha));
        brush.Freeze();
        return brush;
    }

    /// 把整套令牌写入应用资源。界面一律用 DynamicResource 引用，因此换肤时会自动重绘。
    public static void Install(System.Windows.ResourceDictionary resources, bool dark)
    {
        foreach (var (key, light, darkValue) in Palette)
            resources[key] = new SolidColorBrush(FromHex(dark ? darkValue : light));
        resources["NoteRule"] = new SolidColorBrush(FromHex(dark ? NoteRuleDark : NoteRuleLight, 178));
        resources["DialNeutral"] = new SolidColorBrush(FromHex(DialNeutral));

        // 卡片描边在 macOS 上是 border.opacity(0.6)，Windows 端用同一支弱化描边保持一致观感。
        var borderColor = FromHex(dark ? 0x554A40u : 0xE3DBCFu);
        resources["BorderSoft"] = new SolidColorBrush(Color.FromArgb(153, borderColor.R, borderColor.G, borderColor.B));
        // 分段导航的胶囊轨道对应 macOS 的 border.opacity(0.42)。
        resources["NavTrack"] = new SolidColorBrush(Color.FromArgb(107, borderColor.R, borderColor.G, borderColor.B));

        // 按钮悬停 / 按下态：macOS 靠玻璃材质变化，Windows 没有玻璃，
        // 改为在同一色相上明暗微调，观感等价且深浅色都成立。
        var accentFill = FromHex(dark ? 0x98402Du : 0xA84632u);
        resources["AccentHover"] = new SolidColorBrush(Shade(accentFill, 0.10));
        resources["AccentPressed"] = new SolidColorBrush(Shade(accentFill, -0.10));
        var greenFill = FromHex(dark ? 0x405D47u : 0x52705Du);
        resources["GreenHover"] = new SolidColorBrush(Shade(greenFill, 0.10));
        resources["GreenPressed"] = new SolidColorBrush(Shade(greenFill, -0.10));
        var surface = FromHex(dark ? 0x2D2824u : 0xFFFCF6u);
        resources["SurfaceHover"] = new SolidColorBrush(Shade(surface, dark ? 0.08 : -0.03));
        resources["SurfacePressed"] = new SolidColorBrush(Shade(surface, dark ? 0.14 : -0.06));
        resources["Accent"] = new SolidColorBrush(accentFill);

        // 待办页的纸张渐变直接做成现成画刷：GradientStop.Color 用 DynamicResource
        // 引用 Color 资源容易被冻结报错，不如在换肤时重建一次。
        var paper = new LinearGradientBrush(FromHex(dark ? 0x37312Bu : 0xFFFDFAu), FromHex(dark ? 0x2E2923u : 0xF6EFDFu), 90);
        paper.Freeze();
        resources["TodoPaperBrush"] = paper;
    }

    /// amount > 0 向白提亮，< 0 向黑压暗，用于派生交互态颜色。
    public static Color Shade(Color color, double amount)
    {
        var target = amount >= 0 ? 255 : 0;
        var ratio = Math.Abs(amount);
        return Color.FromArgb(color.A,
            (byte)(color.R + (target - color.R) * ratio),
            (byte)(color.G + (target - color.G) * ratio),
            (byte)(color.B + (target - color.B) * ratio));
    }

    /// 交给 Fluent 控件当强调色，让勾选框、开关、进度条、焦点框跟着品牌色走。
    public static Color AccentColor(bool dark) => FromHex(dark ? 0xEEA48Bu : 0xA84632u);

    /// 直接覆盖 WPF-UI 主题字典里的强调色资源键。
    /// Application.Resources 自己的条目优先于 MergedDictionaries，因此这里写入的值一定生效；
    /// 单靠 ApplicationAccentColorManager.Apply 改不到 TextControlFocusedBorderBrush 这类键。
    public static void ApplyFluentAccent(System.Windows.ResourceDictionary resources, bool dark)
    {
        var accent = AccentColor(dark);
        var step = dark ? -0.12 : 0.12;
        var secondary = Shade(accent, step);
        var tertiary = Shade(accent, step * 2);

        SolidColorBrush Frozen(Color c)
        {
            var brush = new SolidColorBrush(c);
            brush.Freeze();
            return brush;
        }

        foreach (var key in new[] { "SystemAccentColorBrush", "SystemAccentColorPrimaryBrush",
                                  "AccentFillColorDefaultBrush", "AccentTextFillColorPrimaryBrush",
                                  "AccentTextFillColorSecondaryBrush", "AccentTextFillColorTertiaryBrush",
                                  "AccentFillColorSelectedTextBackgroundBrush",
                                  "TextControlFocusedBorderBrush", "KeyboardFocusBorderColorBrush" })
            resources[key] = Frozen(accent);
        foreach (var key in new[] { "SystemAccentColorSecondaryBrush", "AccentFillColorSecondaryBrush" })
            resources[key] = Frozen(secondary);
        foreach (var key in new[] { "SystemAccentColorTertiaryBrush", "AccentFillColorTertiaryBrush" })
            resources[key] = Frozen(tertiary);
    }

    public static IEnumerable<string> Keys
    {
        get
        {
            foreach (var (key, _, _) in Palette) yield return key;
            foreach (var derived in new[] { "NoteRule", "DialNeutral", "BorderSoft", "NavTrack", "AccentHover",
                         "AccentPressed", "GreenHover", "GreenPressed", "SurfaceHover", "SurfacePressed", "TodoPaperBrush" })
                yield return derived;
        }
    }
}
