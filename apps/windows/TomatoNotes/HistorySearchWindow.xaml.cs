using System.Windows;
using System.Windows.Controls;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

public partial class HistorySearchWindow : Wpf.Ui.Controls.FluentWindow
{
    private readonly AppState state;

    public HistorySearchWindow(AppState state)
    {
        this.state = state;
        InitializeComponent();
        Loaded += (_, _) => Search();
        Query.Focus();
    }

    private void Query_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != System.Windows.Input.Key.Enter) return;
        Search();
        e.Handled = true;
    }

    private void Query_TextChanged(object sender, TextChangedEventArgs e) => Search();
    private void Filters_Changed(object sender, RoutedEventArgs e) => Search();
    private void DateFilter_Changed(object? sender, SelectionChangedEventArgs e) => Search();

    private void Search()
    {
        if (!IsLoaded) return;
        var query = Query.Text.Trim();
        QueryPlaceholder.Visibility = query.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var kinds = new HashSet<HistorySearchKind>();
        if (FilterTodo.IsChecked == true) kinds.Add(HistorySearchKind.Todo);
        if (FilterNote.IsChecked == true) kinds.Add(HistorySearchKind.Note);
        if (FilterFocus.IsChecked == true) kinds.Add(HistorySearchKind.Focus);
        if (FilterOutcome.IsChecked == true) kinds.Add(HistorySearchKind.Outcome);
        var filters = new HistorySearchFilters(kinds, DayKey(FromDay), DayKey(ThroughDay));
        var results = query.Length == 0 ? [] : new HistorySearchIndex(state.Data).Search(query, filters);
        Results.ItemsSource = results;
        Status.Text = query.Length == 0 ? "输入一个或多个关键词，空格分隔。" : $"找到 {results.Count} 条结果";
    }

    private void Result_Click(object sender, RoutedEventArgs e)
    {
        var result = ((FrameworkElement)sender).Tag as HistorySearchResult;
        if (result is null) return;
        switch (result.Target)
        {
            case { Kind: HistorySearchTargetKind.Note, ID: Guid noteID }:
                state.ShowNote(noteID);
                break;
            case { Kind: HistorySearchTargetKind.Work } work:
                state.OpenWork(work.Scope);
                break;
            case { Kind: HistorySearchTargetKind.Session, ID: Guid sessionID }:
                state.OpenWork(WorkScope.ForSession(sessionID));
                break;
            case { Kind: HistorySearchTargetKind.Todo }:
                state.CurrentTab = 1;
                state.Feedback = "已切到待办页";
                break;
        }
        Close();
    }

    private static string? DayKey(DatePicker picker) => picker.SelectedDate?.ToString("yyyy-MM-dd");
}
