using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
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
