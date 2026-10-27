using System.Windows;
using System.Windows.Controls;

namespace TomatoNotes.Windows;

/// 设置分页，对应 macOS 的 SettingsPage（去掉 Windows 端没有的专注守护页）。
public enum SettingsPage { Overview, Timer, Reminders, Appearance, AI, Data }

public partial class SettingsWindow : Wpf.Ui.Controls.FluentWindow
{
    private static readonly (string Title, string Subtitle)[] PageMeta =
    [
        ("从这里开始", "先开始一轮，再按需要开启更多能力。"),
        ("专注与休息", "选好节奏，让专注和休息自然交替。"),
        ("提醒与快捷键", "选择怎样提醒，以及如何快速唤起。"),
        ("外观", "调整配色，浅色、深色或跟随系统。"),
        ("AI 助手", "连接服务商，整理成果和生成每日回顾。"),
        ("数据与隐私", "了解记录内容，查看和备份本地数据。"),
    ];

    private readonly AppState state;
    private bool loaded;

    public SettingsWindow(AppState state, SettingsPage page = SettingsPage.Overview)
    {
        this.state = state;
        DataContext = state;
        InitializeComponent();
        ProviderBox.ItemsSource = Core.AIProviders.Presets;
        loaded = true;
        SelectPage(page);
    }

    private void SelectPage(SettingsPage page)
    {
        OverviewPane.Visibility = page == SettingsPage.Overview ? Visibility.Visible : Visibility.Collapsed;
        TimerPane.Visibility = page == SettingsPage.Timer ? Visibility.Visible : Visibility.Collapsed;
        RemindersPane.Visibility = page == SettingsPage.Reminders ? Visibility.Visible : Visibility.Collapsed;
        AppearancePane.Visibility = page == SettingsPage.Appearance ? Visibility.Visible : Visibility.Collapsed;
        AIPane.Visibility = page == SettingsPage.AI ? Visibility.Visible : Visibility.Collapsed;
        DataPane.Visibility = page == SettingsPage.Data ? Visibility.Visible : Visibility.Collapsed;

        NavOverview.IsChecked = page == SettingsPage.Overview;
        NavTimer.IsChecked = page == SettingsPage.Timer;
        NavReminders.IsChecked = page == SettingsPage.Reminders;
        NavAppearance.IsChecked = page == SettingsPage.Appearance;
        NavAI.IsChecked = page == SettingsPage.AI;
        NavData.IsChecked = page == SettingsPage.Data;

        PageTitle.Text = PageMeta[(int)page].Title;
        PageSubtitle.Text = PageMeta[(int)page].Subtitle;
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (!loaded || sender is not RadioButton { Tag: string tag }) return;
        if (Enum.TryParse<SettingsPage>(tag, out var page)) SelectPage(page);
    }

    private void NavToTimer_Click(object sender, RoutedEventArgs e) => SelectPage(SettingsPage.Timer);
    private void NavToReminders_Click(object sender, RoutedEventArgs e) => SelectPage(SettingsPage.Reminders);
    private void NavToAI_Click(object sender, RoutedEventArgs e) => SelectPage(SettingsPage.AI);
    private void GoFocus_Click(object sender, RoutedEventArgs e) { state.CurrentTab = 0; Close(); }

    // 旋钮直接写模型属性（无变更通知），所以预设要同步回填控件。
    private void PresetClassic_Click(object sender, RoutedEventArgs e) => ApplyPreset(25, 5, 15, 4);
    private void PresetDeep_Click(object sender, RoutedEventArgs e) => ApplyPreset(50, 10, 20, 4);
    private void ApplyPreset(int focus, int shortBreak, int longBreak, int every)
    {
        FocusDial.Value = focus; ShortDial.Value = shortBreak; LongDial.Value = longBreak; EveryDial.Value = every;
        state.Data.Settings.FocusMinutes = focus;
        state.Data.Settings.ShortBreakMinutes = shortBreak;
        state.Data.Settings.LongBreakMinutes = longBreak;
        state.Data.Settings.LongBreakEvery = every;
    }

    private void Appearance_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!loaded) return;
        // 立即生效并落盘，避免"看着已切换但没保存"的错位状态
        ThemeService.Apply(state.Data.Settings.Appearance);
        state.SaveSettingsCommand.Execute(null);
    }

    private void Provider_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (loaded && ProviderBox.SelectedValue is string id && id != state.CurrentProviderID) state.ChangeProvider(id);
    }
    private void Model_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (loaded && e.AddedItems.Count > 0 && e.AddedItems[0] is string model) state.SetModel(model);
    }
    private void SaveKey_Click(object sender, RoutedEventArgs e)
    {
        state.SaveSettingsCommand.Execute(null);
        state.SaveAPIKey(APIKeyBox.Password);
        APIKeyBox.Clear();
    }
    private void RemoveKey_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("移除当前服务商的本机密钥？", "番茄小记", MessageBoxButton.YesNo) == MessageBoxResult.Yes) state.RemoveAPIKey();
    }
    private async void FetchModels_Click(object sender, RoutedEventArgs e) { state.SaveSettingsCommand.Execute(null); await state.FetchModels(); }
    private async void TestAI_Click(object sender, RoutedEventArgs e) { state.SaveSettingsCommand.Execute(null); await state.TestAI(); }
    private void DataFolder_Click(object sender, RoutedEventArgs e) => state.ShowDataFolder();

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var hotkeys = new[] { state.Data.Settings.TimerHotkey, state.Data.Settings.TodoHotkey, state.Data.Settings.NoteHotkey };
        foreach (var hotkey in hotkeys) hotkey.Enabled = !string.IsNullOrWhiteSpace(hotkey.Letter);
        state.SaveSettingsCommand.Execute(null);
        var main = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault();
        main?.ReapplyHotkeys();
    }

    /// AppState 保存设置后回调：外观可能被改，重新应用一次。
    public void Refresh()
    {
        if (!loaded) return;
        ThemeService.Apply(state.Data.Settings.Appearance);
    }
}
