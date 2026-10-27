using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

public partial class MainWindow : Wpf.Ui.Controls.FluentWindow
{
    internal AppState State { get; }
    private GlobalHotkeyService? hotkeys;
    private bool exiting;

    public MainWindow(AppState state)
    {
        State = state;
        DataContext = state;
        InitializeComponent();
        if (state.LoadError is { } error)
        {
            LoadError.Message = "读取本地数据失败，已禁止写入：" + error;
            LoadError.IsOpen = true;
        }
        // 切页回到顶部，等价 macOS 的 ScrollViewReader 行为
        Nav.SelectionChanged += _ => ContentScroll.ScrollToTop();
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); } else State.PrepareForQuit(); };
        SourceInitialized += (_, _) => RegisterHotkeys();
    }

    internal void ReapplyHotkeys()
    {
        if (hotkeys is null) return;
        foreach (var (id, hotkey, action) in HotkeyActions())
        { var error = hotkeys.Register(id, hotkey, action); if (error is not null) State.Feedback = error; }
    }
    private (int, Hotkey, Action)[] HotkeyActions() => [(1, State.Data.Settings.TimerHotkey, () => Dispatcher.Invoke(() => State.StartCommand.Execute(null))), (2, State.Data.Settings.TodoHotkey, () => Dispatcher.Invoke(ShowQuickTodo)), (3, State.Data.Settings.NoteHotkey, () => Dispatcher.Invoke(State.CreateNote))];
    private void RegisterHotkeys()
    {
        hotkeys = new(this);
        foreach (var (id, hotkey, action) in HotkeyActions())
        { var error = hotkeys.Register(id, hotkey, action); if (error is not null) State.Feedback = error; }
    }

    internal void ShowFromTray() { Show(); WindowState = WindowState.Normal; ShowInTaskbar = true; Activate(); Topmost = true; Topmost = false; }
    internal void ShowQuickTodo() { ShowFromTray(); var dialog = new QuickTodoWindow { Owner = this }; if (dialog.ShowDialog() == true) State.AddTodo(dialog.Value); }
    internal void CreateNote() { ShowFromTray(); State.CreateNote(); }
    internal void ExitApplication() { exiting = true; Close(); State.Dispose(); hotkeys?.Dispose(); System.Windows.Application.Current.Shutdown(); }

    // —— 待办 ——
    private void NewTodo_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        State.AddTodo(State.NewTodo);
        e.Handled = true;
    }
    private void TodoToggle_Click(object sender, RoutedEventArgs e) => State.ToggleTodo(ItemOf<TodoItem>(sender).ID);
    private void TodoDelete_Click(object sender, RoutedEventArgs e)
    {
        var item = ItemOf<TodoItem>(sender);
        State.DeleteTodo(item.ID);
        DeletedBar.Visibility = Visibility.Visible;
        DeletedText.Text = "已删除：" + item.Text;
    }
    private void TodoEdit_Click(object sender, RoutedEventArgs e) => EditTodo(ItemOf<TodoItem>(sender));
    // TextBlock 没有 MouseDoubleClick，用 ClickCount 判定双击改字
    private void TodoText_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount != 2) return;
        EditTodo(ItemOf<TodoItem>(sender));
        e.Handled = true;
    }
    private void EditTodo(TodoItem item)
    {
        var dialog = new InputWindow("修改待办", item.Text) { Owner = this };
        if (dialog.ShowDialog() == true) State.UpdateTodo(item.ID, dialog.Value);
    }
    private void UndoTodo_Click(object sender, RoutedEventArgs e) { State.UndoTodo(); DeletedBar.Visibility = Visibility.Collapsed; }

    // —— 今日 ——
    private void PreviousDay_Click(object sender, RoutedEventArgs e) => State.MoveDay(-1);
    private void NextDay_Click(object sender, RoutedEventArgs e) => State.MoveDay(1);
    private void Today_Click(object sender, RoutedEventArgs e) => State.SelectedDay = State.TodayKey;
    private void DayReview_Click(object sender, RoutedEventArgs e) => State.OpenWork(WorkScope.ForDay(State.SelectedDay));
    private void SessionRow_Click(object sender, RoutedEventArgs e) => State.OpenWork(WorkScope.ForSession(IdOf(sender)));
    private void ShowAllApps_Click(object sender, RoutedEventArgs e) => State.ShowAllApps = !State.ShowAllApps;

    // —— 便签 ——
    private void CreateNote_Click(object sender, RoutedEventArgs e) => State.CreateNote();
    private void OpenNote_Click(object sender, RoutedEventArgs e) => State.ShowNote(IdOf(sender));
    private void ContinueNote_Click(object sender, RoutedEventArgs e) => State.ContinueNote(IdOf(sender));
    private void DeleteNote_Click(object sender, RoutedEventArgs e) => State.DeleteNote(IdOf(sender));
    private void NotesHistory_Click(object sender, RoutedEventArgs e) => State.ShowsHistory = !State.ShowsHistory;
    private void ExportNote_Click(object sender, RoutedEventArgs e)
    {
        var id = IdOf(sender);
        var note = State.Data.Notes.FirstOrDefault(x => x.ID == id);
        if (note is null) return;
        State.ExportNote(id, note.Text);
    }

    // —— 设置总览入口 ——
    private void OpenTimerSettings_Click(object sender, RoutedEventArgs e) => OpenSettings(SettingsPage.Timer);
    private void OpenAISettings_Click(object sender, RoutedEventArgs e) => OpenSettings(SettingsPage.AI);
    private void OpenReminderSettings_Click(object sender, RoutedEventArgs e) => OpenSettings(SettingsPage.Reminders);
    private void OpenAppearanceSettings_Click(object sender, RoutedEventArgs e) => OpenSettings(SettingsPage.Appearance);
    private void OpenDataSettings_Click(object sender, RoutedEventArgs e) => OpenSettings(SettingsPage.Data);
    internal void OpenSettings(SettingsPage page = SettingsPage.Overview)
    {
        var window = new SettingsWindow(State, page) { Owner = this };
        window.ShowDialog();
        State.RefreshAll();
    }

    private static T ItemOf<T>(object sender) where T : class => ((FrameworkElement)sender).DataContext as T
        ?? throw new InvalidOperationException("列表项数据缺失。");
    private static Guid IdOf(object sender) => ((FrameworkElement)sender).Tag is Guid id ? id : Guid.Empty;
}

public sealed class StrikeConverter : IValueConverter
{
    public static StrikeConverter Instance { get; } = new();
    public object Convert(object value, Type type, object parameter, CultureInfo culture) => value is true ? TextDecorations.Strikethrough : null!;
    public object ConvertBack(object value, Type type, object parameter, CultureInfo culture) => Binding.DoNothing;
}
public sealed class MinutesConverter : IValueConverter { public static MinutesConverter Instance { get; } = new(); public object Convert(object v, Type t, object p, CultureInfo c) => ((int)((double)v / 60)).ToString(); public object ConvertBack(object v, Type t, object p, CultureInfo c) => Binding.DoNothing; }
public sealed class DurationConverter : IValueConverter { public static DurationConverter Instance { get; } = new(); public object Convert(object v, Type t, object p, CultureInfo c) => DisplayFormat.Duration((double)v); public object ConvertBack(object v, Type t, object p, CultureInfo c) => Binding.DoNothing; }
