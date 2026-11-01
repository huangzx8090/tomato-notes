using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Globalization;
using TomatoNotes.Core;
using Ui = Wpf.Ui.Controls;

namespace TomatoNotes.Windows;

/// 成果 / 每日回顾窗口：补充文字与图片，交给 AI 汇总，再展示结果。
public sealed class WorkWindow : Ui.FluentWindow
{
    private readonly AppState state;
    private readonly WorkScope scope;
    private readonly TextBox input;
    private readonly WrapPanel images;
    private readonly StackPanel result;
    private readonly TextBlock status;
    private readonly StackPanel activity;
    private bool activityExpanded;
    private bool editingTitle;

    public WorkWindow(AppState state, WorkScope scope)
    {
        this.state = state;
        this.scope = scope;
        Title = scope.SessionID.HasValue ? "本轮工作与成果" : "每日 AI 回顾";
        Width = 680; Height = 760; MinWidth = 560; MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ExtendsContentIntoTitleBar = true;
        WindowBackdropType = Ui.WindowBackdropType.None;
        WindowCornerPreference = Ui.WindowCornerPreference.Round;
        FontFamily = (FontFamily)Application.Current.FindResource("UIFont");
        Foreground = ThemeService.Token("Ink");

        var subtle = (Style)Application.Current.FindResource("SubtleButton");
        var primary = (Style)Application.Current.FindResource("PrimaryButton");
        var hint = (Style)Application.Current.FindResource("HintText");
        var caption = (Style)Application.Current.FindResource("CaptionText");
        var title = (Style)Application.Current.FindResource("TitleText");

        var shell = new Grid { Background = ThemeService.Token("Background") };
        shell.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        shell.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var titleBar = new Ui.TitleBar
        {
            Title = Title,
            Height = 38,
            ShowMaximize = false,
            Padding = new Thickness(16, 0, 0, 0),
            Icon = new Ui.ImageIcon { Source = new BitmapImage(new Uri("pack://application:,,,/Assets/BrandMark.png")) },
        };
        Grid.SetRow(titleBar, 0);
        shell.Children.Add(titleBar);

        var root = new StackPanel { Margin = new Thickness(24, 16, 24, 20) };
        var scroll = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0) };
        Grid.SetRow(scroll, 1);
        shell.Children.Add(scroll);
        Content = shell;

        root.Children.Add(new TextBlock { Text = Title, Style = title });
        root.Children.Add(new TextBlock { Text = "已有记录会自动归集。想补充时，再留一句话或一张图。", Style = hint, Margin = new Thickness(0, 7, 0, 15) });

        // 主题与活动依据放在补充材料之前，与 macOS 的 ActivitySessionDetails 位置一致。
        activity = new StackPanel();
        root.Children.Add(activity);

        input = new TextBox
        {
            Text = state.WorkRecord(scope)?.UserText ?? "",
            Style = (Style)Application.Current.FindResource("BrandTextBox"),
            MinHeight = 108,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalContentAlignment = VerticalAlignment.Top,
        };
        input.LostFocus += (_, _) => state.UpdateWorkText(scope, input.Text);
        root.Children.Add(input);

        images = new WrapPanel();
        root.Children.Add(images);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 16) };
        var add = new Ui.Button { Content = "添加图片（最多 6 张）", Style = subtle };
        add.Click += async (_, _) => { state.UpdateWorkText(scope, input.Text); await state.AddWorkImages(scope); Refresh(); };
        row.Children.Add(add);
        row.Children.Add(new TextBlock { Text = "PNG / JPEG / BMP / GIF，导入为 JPEG", Style = caption, Margin = new Thickness(9, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
        root.Children.Add(row);

        var generate = new Ui.Button { Content = "让 AI 总结工作与成果", Style = primary };
        generate.Click += async (_, _) => { state.UpdateWorkText(scope, input.Text); await state.GenerateReview(scope); Refresh(); };
        root.Children.Add(generate);
        root.Children.Add(new TextBlock { Text = "生成时将对应记录、补充文字及所选图片发送给当前 AI 服务商。AI 可能理解有误，请核对。", Style = caption, Margin = new Thickness(0, 9, 0, 16) });

        status = new TextBlock { Style = hint, Foreground = ThemeService.Token("Accent"), Margin = new Thickness(0, 0, 0, 4) };
        root.Children.Add(status);
        result = new StackPanel();
        root.Children.Add(result);
        Refresh();
    }

    public void Refresh()
    {
        var record = state.WorkRecord(scope);
        RefreshActivity();
        if (record is null) return;
        input.Text = record.UserText;
        images.Children.Clear();
        var subtle = (Style)Application.Current.FindResource("SubtleButton");
        var caption = (Style)Application.Current.FindResource("CaptionText");
        foreach (var image in record.Images)
        {
            var panel = new StackPanel { Width = 138, Margin = new Thickness(0, 8, 10, 0) };
            try
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(state.WorkImagePath(image));
                bitmap.EndInit();
                bitmap.Freeze();
                panel.Children.Add(new Border
                {
                    Width = 128,
                    Height = 96,
                    CornerRadius = new CornerRadius(8),
                    Background = ThemeService.Token("Surface"),
                    BorderBrush = ThemeService.Token("BorderSoft"),
                    BorderThickness = new Thickness(1),
                    Child = new Image { Source = bitmap, Stretch = Stretch.Uniform, Margin = new Thickness(3) },
                });
            }
            catch { /* 图片缺失时只留文件名，不阻断整页 */ }
            panel.Children.Add(new TextBlock { Text = image.Name, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, FontSize = 10, Foreground = ThemeService.Token("Secondary"), Margin = new Thickness(0, 5, 0, 4) });
            var remove = new Ui.Button { Content = "移除", Style = subtle };
            remove.Click += (_, _) => { state.RemoveWorkImage(scope, image.ID); Refresh(); };
            panel.Children.Add(remove);
            images.Children.Add(panel);
        }

        result.Children.Clear();
        status.Text = state.IsGenerating(scope) ? "AI 正在整理文字与图片…" : state.Feedback;
        var summary = record.Summary;
        if (summary is null) return;

        var paperCard = (Style)Application.Current.FindResource("PaperCard");
        var card = new Border { Style = paperCard, Margin = new Thickness(0, 14, 0, 0) };
        var stack = new StackPanel();
        card.Child = stack;

        var header = new DockPanel();
        var headerLeft = new StackPanel { Orientation = Orientation.Horizontal };
        headerLeft.Children.Add(new Ui.SymbolIcon { Symbol = Ui.SymbolRegular.Sparkle24, FontSize = 14, Foreground = ThemeService.Token("Accent"), Margin = new Thickness(0, 1, 7, 0) });
        headerLeft.Children.Add(new TextBlock { Text = "AI 成果总结", Style = (Style)Application.Current.FindResource("TitleText"), FontSize = 14 });
        header.Children.Add(headerLeft);
        var copy = new Ui.Button { Content = "复制", Style = subtle };
        DockPanel.SetDock(copy, Dock.Right);
        copy.Click += (_, _) => Clipboard.SetText(summary.Content.Markdown);
        header.Children.Add(copy);
        stack.Children.Add(header);
        stack.Children.Add(new TextBlock { Text = $"生成于 {summary.GeneratedAt.LocalDateTime:g} · {summary.Model}", Style = caption, Margin = new Thickness(0, 4, 0, 0) });

        AddSection(stack, "做了什么", summary.Content.Activities);
        AddSection(stack, "取得的成果", summary.Content.Outcomes);
        AddSection(stack, "待继续", summary.Content.NextSteps);
        AddSection(stack, "待确认", summary.Content.Uncertainties);
        result.Children.Add(card);
    }

    /// 本轮的主题与活动依据，对应 macOS 的 ActivitySessionDetails。天级回顾没有单一轮次，不展示。
    private void RefreshActivity()
    {
        activity.Children.Clear();
        if (scope.SessionID is not Guid sessionID) return;
        var record = state.WorkRecord(scope);
        var items = ActivityRecorder.Activities(sessionID, state.Data);
        var subtle = (Style)Application.Current.FindResource("SubtleButton");
        var caption = (Style)Application.Current.FindResource("CaptionText");

        var card = new Border { Style = (Style)Application.Current.FindResource("PaperCard"), Margin = new Thickness(0, 0, 0, 16) };
        var stack = new StackPanel();
        card.Child = stack;
        activity.Children.Add(card);

        var header = new DockPanel();
        var headerLeft = new StackPanel { Orientation = Orientation.Horizontal };
        headerLeft.Children.Add(new Ui.SymbolIcon { Symbol = Ui.SymbolRegular.TaskListSquareLtr24, FontSize = 14, Foreground = ThemeService.Token("Accent"), Margin = new Thickness(0, 1, 7, 0) });
        headerLeft.Children.Add(new TextBlock { Text = "主题与活动依据", Style = (Style)Application.Current.FindResource("CardTitle"), VerticalAlignment = VerticalAlignment.Center });
        header.Children.Add(headerLeft);
        var edit = new Ui.Button { Content = "修改主题", Style = subtle, Margin = new Thickness(8, 0, 0, 0) };
        DockPanel.SetDock(edit, Dock.Right);
        edit.Click += (_, _) => { editingTitle = !editingTitle; RefreshActivity(); };
        header.Children.Add(edit);
        stack.Children.Add(header);

        if (editingTitle)
        {
            var row = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var draft = new TextBox
            {
                Text = SessionProgress.Build(sessionID, state.Data)?.Title ?? "",
                Style = (Style)Application.Current.FindResource("BrandTextBox"),
                FontSize = 12,
                MaxLength = 60,
            };
            draft.Loaded += (_, _) => { draft.Focus(); draft.SelectAll(); };
            Grid.SetColumn(draft, 0);
            row.Children.Add(draft);
            var save = new Ui.Button { Content = "保存", Style = subtle, Margin = new Thickness(8, 0, 0, 0) };
            Grid.SetColumn(save, 1);
            row.Children.Add(save);
            save.Click += (_, _) => { state.RenameActivity(sessionID, draft.Text); editingTitle = false; Refresh(); };
            stack.Children.Add(row);
        }

        if (record?.TitleOverride is not null)
            stack.Children.Add(new TextBlock { Text = "使用你修改的名称；AI 后续会参考，当前名称不会被覆盖。", Style = caption, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) });
        else if (record?.ActivityTopic is { } topic)
            stack.Children.Add(new TextBlock { Text = $"AI 初步识别 · {topic.Model} · 可随时修改", Style = caption, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) });

        if (items.Count == 0)
        {
            stack.Children.Add(new TextBlock
            {
                Text = "还没有活动材料。在设置的「AI 助手」里开启自动记录并允许相应来源后，新活动会出现在这里。",
                Style = (Style)Application.Current.FindResource("HintText"),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 10, 0, 0),
            });
            return;
        }

        var toggle = new Ui.Button
        {
            Content = activityExpanded ? $"收起 {items.Count} 条原始活动" : $"查看 {items.Count} 条原始活动",
            Style = subtle,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 10, 0, 0),
        };
        toggle.Click += (_, _) => { activityExpanded = !activityExpanded; RefreshActivity(); };
        stack.Children.Add(toggle);
        if (!activityExpanded) return;

        var list = new StackPanel { Margin = new Thickness(0, 12, 0, 2) };
        foreach (var item in items)
        {
            var row = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var body = new StackPanel { Margin = new Thickness(0, 0, 10, 0) };
            body.Children.Add(new TextBlock { Text = item.Label, FontSize = 12, FontWeight = FontWeights.Medium, TextWrapping = TextWrapping.Wrap, Foreground = ThemeService.Token("Ink") });
            body.Children.Add(new TextBlock { Text = TimeLabel(item), FontSize = 10, Foreground = ThemeService.Token("Secondary"), Margin = new Thickness(0, 4, 0, 0) });
            if (!string.IsNullOrEmpty(item.Detail))
                body.Children.Add(new TextBlock { Text = item.Detail, FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = ThemeService.Token("Secondary"), Margin = new Thickness(0, 4, 0, 0) });
            Grid.SetColumn(body, 0);
            row.Children.Add(body);
            var remove = new Ui.Button { Content = "删除", Style = subtle, VerticalAlignment = VerticalAlignment.Top };
            System.Windows.Automation.AutomationProperties.SetName(remove, "删除活动：" + item.Title);
            remove.Click += (_, _) => { state.UpdateWorkText(scope, input.Text); state.RemoveActivity(item.ID); Refresh(); };
            Grid.SetColumn(remove, 1);
            row.Children.Add(remove);
            list.Children.Add(row);
        }
        stack.Children.Add(list);
        stack.Children.Add(new TextBlock
        {
            Text = items.Any(x => x.Kind == ActivityKind.ChromePage)
                ? "删除会移除本轮相同材料的记录及依赖的 AI 总结，并在这一轮停止记录该材料。浏览时间是采样估计，不代表读完或学会。"
                : "删除会移除本轮相同材料的记录及依赖的 AI 总结，并在这一轮停止记录该材料。",
            Style = caption,
            TextWrapping = TextWrapping.Wrap,
        });
    }

    /// macOS 的 timeLabel：浏览类材料带起止时间与采样停留，其余只标一个时间点。
    private static string TimeLabel(FocusActivity item)
    {
        var start = item.StartedAt.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
        if (item.Kind != ActivityKind.ChromePage) return start;
        var end = item.EndedAt.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
        return $"{start}–{end} · {item.Site} · 约 {DisplayFormat.Duration(item.Seconds)}";
    }

    private static void AddSection(Panel root, string title, IEnumerable<string> lines)
    {
        var items = lines.ToList();
        if (items.Count == 0) return;
        root.Children.Add(new TextBlock { Text = title, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = ThemeService.Token("Ink"), Margin = new Thickness(0, 15, 0, 5) });
        foreach (var line in items)
            root.Children.Add(new TextBlock { Text = "• " + line, FontSize = 12, LineHeight = 19, TextWrapping = TextWrapping.Wrap, Foreground = ThemeService.Token("Ink"), Margin = new Thickness(0, 3, 0, 0) });
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        state.UpdateWorkText(scope, input.Text);
        base.OnClosing(e);
    }
}
