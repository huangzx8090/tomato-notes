using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using TomatoNotes.Core;
using Ui = Wpf.Ui.Controls;

namespace TomatoNotes.Windows;

/// 便签浮窗：纸质黄底、便签色文字，与 macOS 的便签窗口同一套令牌。
public sealed class NoteWindow : Ui.FluentWindow
{
    private readonly AppState state;
    private readonly StickyNote note;
    private readonly TextBox editor;
    private readonly Border paper;
    private readonly DispatcherTimer save = new() { Interval = TimeSpan.FromMilliseconds(600) };
    private readonly TextBlock status = new() { FontSize = 11, VerticalAlignment = VerticalAlignment.Center };
    private bool closing;

    public NoteWindow(AppState state, StickyNote note)
    {
        this.state = state;
        this.note = note;
        Title = note.Title;
        Width = Math.Clamp(note.Width, 240, 1200);
        Height = Math.Clamp(note.Height, 200, 1000);
        MinWidth = 240; MinHeight = 200;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        ExtendsContentIntoTitleBar = true;
        WindowBackdropType = Ui.WindowBackdropType.None;
        WindowCornerPreference = Ui.WindowCornerPreference.Round;
        FontFamily = (FontFamily)Application.Current.FindResource("UIFont");
        ResizeMode = ResizeMode.CanResize;

        var fallbackLeft = 160 + state.Data.Notes.Count(x => x.IsOpen) % 8 * 24;
        Left = note.X ?? fallbackLeft;
        Top = note.Y ?? 160;
        Loaded += (_, _) =>
        {
            var area = SystemParameters.WorkArea;
            Width = Math.Min(Width, area.Width);
            Height = Math.Min(Height, area.Height);
            Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        };

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var titleBar = new Ui.TitleBar { Title = note.Title, Height = 32, ShowMaximize = false, FontSize = 12 };
        Grid.SetRow(titleBar, 0);
        root.Children.Add(titleBar);

        var toolbar = new DockPanel { Margin = new Thickness(12, 0, 12, 8) };
        Grid.SetRow(toolbar, 1);
        root.Children.Add(toolbar);

        // 先建编辑器：下面的按钮回调会引用它，先赋值可避开“可能为空”告警
        editor = new TextBox { Style = (Style)Application.Current.FindResource("NoteTextBox"), Text = note.Text };
        editor.TextChanged += (_, _) => { save.Stop(); save.Start(); };

        var subtle = (Style)Application.Current.FindResource("SubtleButton");
        var convert = new Ui.Button { Content = "按行转待办", Style = subtle, Margin = new Thickness(7, 0, 0, 0) };
        convert.Click += (_, _) =>
        {
            Flush();
            var count = state.ConvertNoteToTodos(editor.SelectedText.Length > 0 ? editor.SelectedText : editor.Text);
            status.Text = $"已添加 {count} 条待办";
        };
        var export = new Ui.Button { Content = "导出 TXT", Style = subtle, Margin = new Thickness(7, 0, 0, 0) };
        export.Click += (_, _) => { Flush(); state.ExportNote(note.ID, editor.Text); status.Text = state.Feedback; };
        DockPanel.SetDock(status, Dock.Left);
        DockPanel.SetDock(export, Dock.Right);
        DockPanel.SetDock(convert, Dock.Right);
        toolbar.Children.Add(status);
        toolbar.Children.Add(export);
        toolbar.Children.Add(convert);

        Grid.SetRow(editor, 2);
        root.Children.Add(editor);

        // 纸色铺满整个客户区，避免 FluentWindow 自己的背景把便签色盖掉
        paper = new Border { Child = root };
        Content = paper;
        ApplyTheme();
        ThemeService.Changed += ApplyTheme;
        Closed += (_, _) => ThemeService.Changed -= ApplyTheme;

        save.Tick += (_, _) =>
        {
            save.Stop();
            state.UpdateNote(note.ID, editor.Text);
            Title = note.Title;
            titleBar.Title = note.Title;
            status.Text = "已自动保存";
        };
        LocationChanged += (_, _) => SaveFrame();
        SizeChanged += (_, _) => SaveFrame();
        Closing += (_, _) => { Flush(); if (!state.IsQuitting) state.SetNoteOpen(note.ID, false); closing = true; };
    }

    private void ApplyTheme()
    {
        Dispatcher.Invoke(() =>
        {
            paper.Background = ThemeService.Token("NotePaper");
            Foreground = ThemeService.Token("NoteInk");
            status.Foreground = ThemeService.Token("NoteAction");
        });
    }

    private void SaveFrame() { if (!closing && IsLoaded) state.UpdateNoteFrame(note.ID, this); }

    public void Flush()
    {
        save.Stop();
        state.UpdateNote(note.ID, editor.Text);
        Title = note.Title;
        SaveFrame();
    }
}

/// 快速待办：对应 macOS 的 QuickTodoView。
public sealed class QuickTodoWindow : Ui.FluentWindow
{
    public string Value => box.Text;
    private readonly TextBox box;

    public QuickTodoWindow()
    {
        Title = "快速待办";
        Width = 390; Height = 200; SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Topmost = true;
        ExtendsContentIntoTitleBar = true;
        WindowBackdropType = Ui.WindowBackdropType.None;
        WindowCornerPreference = Ui.WindowCornerPreference.Round;
        FontFamily = (FontFamily)Application.Current.FindResource("UIFont");
        Foreground = ThemeService.Token("Ink");
        ShowInTaskbar = false;

        var root = new Grid { Background = ThemeService.Token("Background") };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(new Ui.TitleBar { Title = "快速待办", Height = 30, ShowMinimize = false, ShowMaximize = false, FontSize = 12 });

        var stack = new StackPanel { Margin = new Thickness(22, 8, 22, 20) };
        Grid.SetRow(stack, 1);
        var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        header.Children.Add(new Ui.SymbolIcon { Symbol = Ui.SymbolRegular.TaskListSquareLtr24, FontSize = 14, Foreground = ThemeService.Token("Accent"), Margin = new Thickness(0, 1, 7, 0) });
        header.Children.Add(new TextBlock { Text = "随手记一件小事", FontSize = 14, FontWeight = FontWeights.SemiBold });
        stack.Children.Add(header);

        box = new TextBox { Style = (Style)Application.Current.FindResource("BrandTextBox"), FontSize = 14 };
        box.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Enter && !string.IsNullOrWhiteSpace(box.Text)) DialogResult = true;
            else if (e.Key == System.Windows.Input.Key.Escape) DialogResult = false;
        };
        stack.Children.Add(box);
        stack.Children.Add(new TextBlock { Text = "Enter 保存到今天 · Esc 返回", Style = (Style)Application.Current.FindResource("HintText"), Margin = new Thickness(0, 9, 0, 0) });
        root.Children.Add(stack);
        Content = root;
        Loaded += (_, _) => box.Focus();
    }
}

/// 单行输入对话框：改待办文字等场景。
public sealed class InputWindow : Ui.FluentWindow
{
    private readonly TextBox box;
    public string Value => box.Text;

    public InputWindow(string title, string text)
    {
        Title = title;
        Width = 420; SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ExtendsContentIntoTitleBar = true;
        WindowBackdropType = Ui.WindowBackdropType.None;
        WindowCornerPreference = Ui.WindowCornerPreference.Round;
        FontFamily = (FontFamily)Application.Current.FindResource("UIFont");
        Foreground = ThemeService.Token("Ink");
        ShowInTaskbar = false;

        var root = new Grid { Background = ThemeService.Token("Background") };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(new Ui.TitleBar { Title = title, Height = 30, ShowMinimize = false, ShowMaximize = false, FontSize = 12 });

        var stack = new StackPanel { Margin = new Thickness(22, 8, 22, 20) };
        Grid.SetRow(stack, 1);
        box = new TextBox { Text = text, Style = (Style)Application.Current.FindResource("BrandTextBox"), FontSize = 13 };
        box.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Enter && !string.IsNullOrWhiteSpace(box.Text)) DialogResult = true;
            else if (e.Key == System.Windows.Input.Key.Escape) DialogResult = false;
        };
        stack.Children.Add(box);
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        var cancel = new Ui.Button { Content = "取消", Style = (Style)Application.Current.FindResource("SubtleButton"), MinWidth = 76 };
        cancel.Click += (_, _) => DialogResult = false;
        var ok = new Ui.Button { Content = "保存", Style = (Style)Application.Current.FindResource("PrimaryButton"), MinWidth = 76, Margin = new Thickness(9, 0, 0, 0) };
        ok.Click += (_, _) => { if (!string.IsNullOrWhiteSpace(box.Text)) DialogResult = true; };
        row.Children.Add(cancel);
        row.Children.Add(ok);
        stack.Children.Add(row);
        root.Children.Add(stack);
        Content = root;
        Loaded += (_, _) => { box.Focus(); box.SelectAll(); };
    }
}
