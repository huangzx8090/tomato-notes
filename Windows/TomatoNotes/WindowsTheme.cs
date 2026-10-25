using Microsoft.Win32;
namespace TomatoNotes.Windows;
internal static class WindowsTheme
{
    public static bool IsDark()
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int value && value == 0; }
        catch { return false; }
    }
}
