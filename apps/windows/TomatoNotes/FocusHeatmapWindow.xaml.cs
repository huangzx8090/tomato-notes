using System.Windows;
using TomatoNotes.Core;
using Ui = Wpf.Ui.Controls;

namespace TomatoNotes.Windows;

public partial class FocusHeatmapWindow : Ui.FluentWindow
{
    private readonly AppState state;
    private int pageOffset;

    public FocusHeatmapWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    private void Previous_Click(object sender, RoutedEventArgs e) { pageOffset++; Refresh(); }
    private void Next_Click(object sender, RoutedEventArgs e) { if (pageOffset > 0) { pageOffset--; Refresh(); } }

    private void Refresh()
    {
        var range = FocusHeatmapRange.Build(state.Data.Intervals, 13, pageOffset);
        var weeks = range.Weeks.Select(week => new HeatmapWeekRow(week.Days.Select(day => new HeatmapDayRow(day)).ToList())).ToList();
        Weeks.ItemsSource = weeks;
        RangeLabel.Text = $"{range.StartDay.Replace("-", ".")} - {range.EndDay.Replace("-", ".")}";
        SummaryLabel.Text = $"累计专注 {DisplayFormat.Duration(range.TotalSeconds)}，共 {range.ActiveDays} 天留下投入。";
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

internal sealed record HeatmapWeekRow(List<HeatmapDayRow> Days);
internal sealed class HeatmapDayRow(FocusHeatmapDay day)
{
    public string Day { get; } = day.Day;
    public int Intensity { get; } = day.Intensity;
    public bool IsFuture { get; } = day.IsFuture;
    public string Tooltip { get; } = $"{day.Date:yyyy-MM-dd dddd} · {(day.IsFuture ? "未到" : DisplayFormat.Duration(day.Seconds))}";
}
