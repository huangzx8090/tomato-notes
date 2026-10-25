using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;
public partial class MainWindow : Window
{
    internal AppState State { get; }
    private GlobalHotkeyService? hotkeys;
    private bool exiting;
    public MainWindow(AppState state)
    {
        State = state; DataContext = state; InitializeComponent(); LoadError.Text = state.LoadError is null ? "" : "读取本地数据失败，已禁止写入：" + state.LoadError;
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
    private void Tab_Click(object sender, RoutedEventArgs e) { State.CurrentTab = int.Parse((string)((Button)sender).Tag); State.RefreshHistory(); }
    private void NewTodo_KeyDown(object sender, System.Windows.Input.KeyEventArgs e) { if (e.Key == Key.Enter) { State.AddTodo(State.NewTodo); e.Handled = true; } }
    private void TodoToggle_Click(object sender, RoutedEventArgs e) => State.ToggleTodo(((TodoItem)((FrameworkElement)sender).DataContext).ID);
    private void TodoDelete_Click(object sender, RoutedEventArgs e) { var item = (TodoItem)((FrameworkElement)sender).DataContext; State.DeleteTodo(item.ID); DeletedBar.Visibility = Visibility.Visible; DeletedText.Text = "已删除：" + item.Text; }
    private void TodoEdit_Click(object sender, RoutedEventArgs e) { var item = (TodoItem)((FrameworkElement)sender).DataContext; var dialog = new InputWindow("修改待办", item.Text) { Owner = this }; if (dialog.ShowDialog() == true) State.UpdateTodo(item.ID, dialog.Value); }
    private void UndoTodo_Click(object sender, RoutedEventArgs e) { State.UndoTodo(); DeletedBar.Visibility = Visibility.Collapsed; }
    private void PreviousDay_Click(object sender, RoutedEventArgs e) => State.MoveDay(-1);
    private void NextDay_Click(object sender, RoutedEventArgs e) => State.MoveDay(1);
    private void Today_Click(object sender, RoutedEventArgs e) => State.SelectedDay = State.TodayKey;
    private void DayReview_Click(object sender, RoutedEventArgs e) => State.OpenWork(WorkScope.ForDay(State.SelectedDay));
    private void SessionReview_Click(object sender, RoutedEventArgs e) => State.OpenWork(WorkScope.ForSession(((FocusSession)((FrameworkElement)sender).DataContext).ID));
    private void CreateNote_Click(object sender, RoutedEventArgs e) => State.CreateNote();
    private void OpenNote_Click(object sender, RoutedEventArgs e) => State.ShowNote(((StickyNote)((FrameworkElement)sender).DataContext).ID);
    private void ContinueNote_Click(object sender, RoutedEventArgs e) => State.ContinueNote(((StickyNote)((FrameworkElement)sender).DataContext).ID);
    private void DeleteNote_Click(object sender, RoutedEventArgs e) => State.DeleteNote(((StickyNote)((FrameworkElement)sender).DataContext).ID);
    private void Settings_Click(object sender, RoutedEventArgs e) { var window = new SettingsWindow(State) { Owner = this }; window.ShowDialog(); State.RefreshAll(); }
    private void DataFolder_Click(object sender, RoutedEventArgs e) => State.ShowDataFolder();
}

public sealed class StrikeConverter : IValueConverter
{
    public static StrikeConverter Instance { get; } = new();
    public object Convert(object value, Type type, object parameter, CultureInfo culture) => value is true ? TextDecorations.Strikethrough : null!;
    public object ConvertBack(object value, Type type, object parameter, CultureInfo culture) => Binding.DoNothing;
}
public sealed class MinutesConverter : IValueConverter { public static MinutesConverter Instance { get; } = new(); public object Convert(object v, Type t, object p, CultureInfo c) => ((int)((double)v / 60)).ToString(); public object ConvertBack(object v, Type t, object p, CultureInfo c) => Binding.DoNothing; }
public sealed class DurationConverter : IValueConverter { public static DurationConverter Instance { get; } = new(); public object Convert(object v, Type t, object p, CultureInfo c) => DisplayFormat.Duration((double)v); public object ConvertBack(object v, Type t, object p, CultureInfo c) => Binding.DoNothing; }
