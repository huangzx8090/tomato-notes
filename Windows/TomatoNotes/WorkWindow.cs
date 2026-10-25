using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;
public sealed class WorkWindow : Window
{
    private readonly AppState state;
    private readonly WorkScope scope;
    private readonly System.Windows.Controls.TextBox input;
    private readonly WrapPanel images;
    private readonly StackPanel result;
    private readonly TextBlock status;
    public WorkWindow(AppState state, WorkScope scope)
    {
        this.state = state; this.scope = scope; Title = scope.SessionID.HasValue ? "本轮工作与成果" : "每日 AI 回顾"; Width = 660; Height = 750; MinWidth = 550; MinHeight = 500; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var root = new StackPanel { Margin = new Thickness(25) }; var scroll = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; Content = scroll;
        root.Children.Add(new TextBlock { Text = Title, FontSize = 24, FontWeight = FontWeights.SemiBold });
        root.Children.Add(new TextBlock { Text = "已有记录会自动归集。想补充时，再留一句话或一张图。", Style = (Style)FindResource("HintText"), Margin = new Thickness(0, 7, 0, 15) });
        input = new System.Windows.Controls.TextBox { Text = state.WorkRecord(scope)?.UserText ?? "", MinHeight = 100, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalContentAlignment = VerticalAlignment.Top };
        input.LostFocus += (_, _) => state.UpdateWorkText(scope, input.Text); root.Children.Add(input);
        images = new(); root.Children.Add(images); var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 16) };
        var add = new Button { Content = "添加图片（最多 6 张）" }; add.Click += async (_, _) => { state.UpdateWorkText(scope, input.Text); await state.AddWorkImages(scope); Refresh(); };
        row.Children.Add(add); row.Children.Add(new TextBlock { Text = "  PNG / JPEG / BMP / GIF，导入为 JPEG", Style = (Style)FindResource("HintText"), Margin = new Thickness(7, 0, 0, 0) }); root.Children.Add(row);
        var generate = new Button { Content = "让 AI 总结工作与成果", Style = (Style)FindResource("PrimaryButton"), Padding = new Thickness(15, 10, 15, 10) }; generate.Click += async (_, _) => { state.UpdateWorkText(scope, input.Text); await state.GenerateReview(scope); Refresh(); }; root.Children.Add(generate);
        root.Children.Add(new TextBlock { Text = "生成时将对应记录、补充文字及所选图片发送给当前 AI 服务商。AI 可能理解有误，请核对。", Style = (Style)FindResource("HintText"), Margin = new Thickness(0, 8, 0, 16) });
        status = new() { Style = (Style)FindResource("HintText"), Foreground = (System.Windows.Media.Brush)FindResource("Accent") }; root.Children.Add(status); result = new(); root.Children.Add(result); Refresh();
    }
    public void Refresh()
    {
        var record = state.WorkRecord(scope); if (record is null) return; input.Text = record.UserText; images.Children.Clear();
        foreach (var image in record.Images)
        {
            var panel = new StackPanel { Width = 135, Margin = new Thickness(0, 8, 10, 0) }; try { var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.UriSource = new(state.WorkImagePath(image)); bitmap.EndInit(); bitmap.Freeze(); panel.Children.Add(new Image { Source = bitmap, Width = 125, Height = 95, Stretch = System.Windows.Media.Stretch.Uniform }); } catch { }
            panel.Children.Add(new TextBlock { Text = image.Name, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, FontSize = 10 }); var remove = new Button { Content = "移除", Padding = new Thickness(5, 2, 5, 2) }; remove.Click += (_, _) => { state.RemoveWorkImage(scope, image.ID); Refresh(); }; panel.Children.Add(remove); images.Children.Add(panel);
        }
        result.Children.Clear(); status.Text = state.IsGenerating(scope) ? "AI 正在整理文字与图片…" : state.Feedback;
        var summary = record.Summary; if (summary is null) return;
        var card = new Border { Style = (Style)FindResource("Card"), Margin = new Thickness(0, 15, 0, 0) }; var stack = new StackPanel(); card.Child = stack;
        var header = new DockPanel(); header.Children.Add(new TextBlock { Text = "AI 成果总结", Style = (Style)FindResource("TitleText") }); var copy = new Button { Content = "复制", Padding = new Thickness(8, 3, 8, 3) }; DockPanel.SetDock(copy, Dock.Right); copy.Click += (_, _) => Clipboard.SetText(summary.Content.Markdown); header.Children.Add(copy); stack.Children.Add(header);
        stack.Children.Add(new TextBlock { Text = $"生成于 {summary.GeneratedAt.LocalDateTime:g} · {summary.Model}", Style = (Style)FindResource("HintText") });
        AddSection(stack, "做了什么", summary.Content.Activities); AddSection(stack, "取得的成果", summary.Content.Outcomes); AddSection(stack, "待继续", summary.Content.NextSteps); AddSection(stack, "待确认", summary.Content.Uncertainties); result.Children.Add(card);
    }
    private static void AddSection(System.Windows.Controls.Panel root, string title, IEnumerable<string> lines) { if (!lines.Any()) return; root.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 14, 0, 4) }); foreach (var line in lines) root.Children.Add(new TextBlock { Text = "• " + line, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) }); }
    protected override void OnClosing(System.ComponentModel.CancelEventArgs e) { state.UpdateWorkText(scope, input.Text); base.OnClosing(e); }
}
