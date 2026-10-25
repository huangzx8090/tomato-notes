using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace TomatoNotes.Windows;
public partial class SettingsWindow : Window
{
    private readonly AppState state;
    private bool loaded;
    public SettingsWindow(AppState state)
    {
        this.state = state; DataContext = state; InitializeComponent(); ProviderBox.ItemsSource = Core.AIProviders.Presets; loaded = true; ApplyAppearance();
    }
    private void Provider_Changed(object sender, SelectionChangedEventArgs e) { if (loaded && ProviderBox.SelectedValue is string id && id != state.CurrentProviderID) state.ChangeProvider(id); }
    private void Model_Changed(object sender, SelectionChangedEventArgs e) { if (loaded && e.AddedItems.Count > 0 && e.AddedItems[0] is string model) state.SetModel(model); }
    private void SaveKey_Click(object sender, RoutedEventArgs e) { state.SaveSettingsCommand.Execute(null); state.SaveAPIKey(APIKeyBox.Password); APIKeyBox.Clear(); }
    private void RemoveKey_Click(object sender, RoutedEventArgs e) { if (MessageBox.Show("移除当前服务商的本机密钥？", "番茄小记", MessageBoxButton.YesNo) == MessageBoxResult.Yes) state.RemoveAPIKey(); }
    private async void FetchModels_Click(object sender, RoutedEventArgs e) { state.SaveSettingsCommand.Execute(null); await state.FetchModels(); }
    private async void TestAI_Click(object sender, RoutedEventArgs e) { state.SaveSettingsCommand.Execute(null); await state.TestAI(); }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var hotkeys = new[] { state.Data.Settings.TimerHotkey, state.Data.Settings.TodoHotkey, state.Data.Settings.NoteHotkey };
        foreach (var hotkey in hotkeys) hotkey.Enabled = !string.IsNullOrWhiteSpace(hotkey.Letter);
        state.SaveSettingsCommand.Execute(null); var main = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault(); main?.ReapplyHotkeys();
    }
    public void Refresh() { ApplyAppearance(); }
    private void ApplyAppearance()
    {
        var appearance = state.Data.Settings.Appearance;
        var dark = appearance == "dark" || appearance == "system" && WindowsTheme.IsDark();
        var resources = Application.Current.Resources;
        resources["Background"] = new SolidColorBrush(dark ? Color.FromRgb(38, 38, 35) : Color.FromRgb(247, 243, 235));
        resources["Surface"] = new SolidColorBrush(dark ? Color.FromRgb(49, 49, 45) : Color.FromRgb(255, 252, 247));
        resources["Ink"] = new SolidColorBrush(dark ? Color.FromRgb(237, 233, 221) : Color.FromRgb(57, 54, 47));
        resources["Secondary"] = new SolidColorBrush(dark ? Color.FromRgb(175, 171, 159) : Color.FromRgb(124, 120, 110));
        resources["Border"] = new SolidColorBrush(dark ? Color.FromRgb(75, 74, 65) : Color.FromRgb(229, 221, 208));
        foreach (var window in Application.Current.Windows.OfType<Window>()) { window.Background = (Brush)resources["Background"]; window.Foreground = (Brush)resources["Ink"]; }
    }
}
