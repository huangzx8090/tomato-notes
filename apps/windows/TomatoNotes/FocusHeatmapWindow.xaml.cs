using System.Windows;
using System.Windows.Controls;
using TomatoNotes.Core;
using Ui = Wpf.Ui.Controls;

namespace TomatoNotes.Windows;

public partial class FocusHeatmapWindow : Ui.FluentWindow
{
    private readonly AppState state;
    private int pageOffset;
    private int weekCount = 13;
    private bool loaded;

    public FocusHeatmapWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        Loaded += (_, _) => { loaded = true; Refresh(); };
    }

    private void Previous_Click(object sender, RoutedEventArgs e) { pageOffset++; Refresh(); }
    private void Next_Click(object sender, RoutedEventArgs e) { if (pageOffset > 0) { pageOffset--; Refresh(); } }

    private void Range_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!loaded || RangeBox.SelectedItem is not ComboBoxItem { Tag: string tag } || !int.TryParse(tag, out var count)) return;
        if (count == weekCount) return;
        weekCount = count;
        // 切换跨度后回到包含本周的那一页，避免延续旧的页偏移。
        pageOffset = 0;
        Refresh();
    }

    private void Refresh()
    {
        var range = FocusHeatmapRange.Build(state.Data.Intervals, weekCount, pageOffset);
        Weeks.ItemsSource = HeatmapProjections.Weeks(range, null);
        RangeLabel.Text = $"{range.StartDay.Replace("-", ".")} - {range.EndDay.Replace("-", ".")}";
        SummaryLabel.Text = $"近 {weekCount} 周累计专注 {DisplayFormat.Duration(range.TotalSeconds)}，共 {range.ActiveDays} 天留下投入。";
        NextButton.IsEnabled = pageOffset > 0;
    }

    private void Day_Click(object sender, RoutedEventArgs e)
    {
        var day = ((FrameworkElement)sender).Tag as HeatmapDayRow;
        if (day is null || day.IsFuture) return;
        state.SelectedDay = day.Day;
        state.CurrentTab = 2;
        Close();
    }
}
