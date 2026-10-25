using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;
public sealed class NoteWindow : Window
{
    private readonly AppState state;
    private readonly StickyNote note;
    private readonly TextBox editor;
    private readonly DispatcherTimer save = new() { Interval = TimeSpan.FromMilliseconds(600) };
    private readonly TextBlock status = new() { FontSize = 11, Foreground = Brushes.DimGray };
    private bool closing;
    public NoteWindow(AppState state, StickyNote note)
    {
        this.state = state; this.note = note; Title = note.Title; Width = Math.Clamp(note.Width, 240, 1200); Height = Math.Clamp(note.Height, 200, 1000); MinWidth = 240; MinHeight = 200; Topmost = true; Background = new SolidColorBrush(Color.FromRgb(255, 249, 220)); WindowStartupLocation = WindowStartupLocation.Manual;
        Left = note.X ?? 160 + state.Data.Notes.Count(x => x.IsOpen) % 8 * 24; Top = note.Y ?? 160;
        Loaded += (_, _) => { var area = SystemParameters.WorkArea; Width = Math.Min(Width, area.Width); Height = Math.Min(Height, area.Height); Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width)); Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height)); };
        var root = new DockPanel { Margin = new Thickness(8) }; var toolbar = new DockPanel { Margin = new Thickness(0, 0, 0, 7) }; DockPanel.SetDock(toolbar, Dock.Top); root.Children.Add(toolbar);
        var convert = new Button { Content = "按行转待办", Padding = new Thickness(7) }; convert.Click += (_, _) => { Flush(); var count = state.ConvertNoteToTodos(editor.SelectedText.Length > 0 ? editor.SelectedText : editor.Text); status.Text = $"已添加 {count} 条待办"; };
        var export = new Button { Content = "导出 TXT", Padding = new Thickness(7), Margin = new Thickness(7, 0, 0, 0) }; export.Click += (_, _) => { Flush(); state.ExportNote(note.ID, editor.Text); status.Text = state.Feedback; };
        DockPanel.SetDock(status, Dock.Left); toolbar.Children.Add(status); DockPanel.SetDock(export, Dock.Right); toolbar.Children.Add(export); DockPanel.SetDock(convert, Dock.Right); toolbar.Children.Add(convert);
        editor = new TextBox { Text = note.Text, AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = Brushes.Transparent, BorderThickness = new Thickness(0), FontSize = 15, Padding = new Thickness(9), VerticalContentAlignment = VerticalAlignment.Top };
        editor.TextChanged += (_, _) => { save.Stop(); save.Start(); }; root.Children.Add(editor); Content = root;
        save.Tick += (_, _) => { save.Stop(); state.UpdateNote(note.ID, editor.Text); Title = note.Title; status.Text = "已自动保存"; };
        LocationChanged += (_, _) => SaveFrame(); SizeChanged += (_, _) => SaveFrame();
        Closing += (_, _) => { Flush(); if (!state.IsQuitting) state.SetNoteOpen(note.ID, false); closing = true; };
    }
    private void SaveFrame() { if (!closing && IsLoaded) state.UpdateNoteFrame(note.ID, this); }
    public void Flush() { save.Stop(); state.UpdateNote(note.ID, editor.Text); Title = note.Title; SaveFrame(); }
}

public sealed class QuickTodoWindow : Window
{
    public string Value => box.Text;
    private readonly TextBox box;
    public QuickTodoWindow()
    {
        Title = "快速待办"; Width = 390; Height = 185; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner; Topmost = true;
        var stack = new StackPanel { Margin = new Thickness(20) }; stack.Children.Add(new TextBlock { Text = "随手记一件小事", FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) });
        box = new(); box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter && !string.IsNullOrWhiteSpace(box.Text)) { DialogResult = true; } else if (e.Key == System.Windows.Input.Key.Escape) DialogResult = false; }; stack.Children.Add(box);
        stack.Children.Add(new TextBlock { Text = "Enter 保存到今天 · Esc 返回", Style = (Style)FindResource("HintText"), Margin = new Thickness(0, 8, 0, 0) }); Content = stack; Loaded += (_, _) => box.Focus();
    }
}
public sealed class InputWindow : Window
{
    private readonly TextBox box; public string Value => box.Text;
    public InputWindow(string title, string text)
    {
        Title = title; Width = 400; Height = 170; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var stack = new StackPanel { Margin = new Thickness(20) }; box = new() { Text = text }; stack.Children.Add(box); var button = new Button { Content = "保存", Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = HorizontalAlignment.Right }; button.Click += (_, _) => { if (!string.IsNullOrWhiteSpace(box.Text)) DialogResult = true; }; stack.Children.Add(button); Content = stack;
    }
}
