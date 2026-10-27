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
        Weeks.ItemsSource = HeatmapProjections.Weeks(range, null);
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
