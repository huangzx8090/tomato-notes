using TomatoNotes.Core;

namespace TomatoNotes.Windows;

/// 今日页「专注时使用的 App」一行：名称、时长文本，以及相对当日专注总时长的占比。
public sealed record AppUsageRow(string Name, string Duration, double Ratio);

/// 时间线里的一轮专注。标题依次取用户改名、本轮目标、AI 识别的主题，
/// 最后退回本轮勾选完成的第一件事。同主题多于一轮时，组头文字挂在第一轮上。
public sealed record SessionRow(Guid ID, string Title, string Detail, string? Todos, bool Completed, bool InProgress, string? GroupTitle = null, string? GroupDetail = null);

/// 当天待办一行，用于今日页的回顾卡片。
public sealed record TodoDayRow(Guid ID, string Text, bool CompletedOnDay, string Detail);

/// 专注页顶部的「这一轮，留下了进展」卡片。
public sealed record ProgressCard(Guid ID, string Title, string Time, string Detail, string? Todos, bool InProgress);

/// 便签列表里的一张卡片。
public sealed record NoteRow(Guid ID, string Title, string Preview, string Meta, bool IsOpen, bool Historical);

/// 历史便签按天分组，对应 macOS 的 NoteDayGroup。
public sealed record NoteDayGroup(string DayLabel, int Count, List<NoteRow> Notes);

/// 待办页的顺延候选。选择状态保存在行对象里，批量操作读取当前选择。
public sealed class CarryoverRow
{
    public required Guid ID { get; init; }
    public required string Text { get; init; }
    public required string Detail { get; init; }
    public bool IsSelected { get; set; }
}

/// 热力图里的一格。IsSelected 用于紧凑视图描出当前查看的那一天。
public sealed class HeatmapDayRow
{
    public required string Day { get; init; }
    public required int Intensity { get; init; }
    public required bool IsFuture { get; init; }
    public required bool IsSelected { get; init; }
    public required string Tooltip { get; init; }
}

/// 热力图里的一周，紧凑视图按列排布、独立窗口按行排布，共用同一份投影。
public sealed record HeatmapWeekRow(List<HeatmapDayRow> Days);

public static class HeatmapProjections
{
    public static List<HeatmapWeekRow> Weeks(FocusHeatmapRange range, string? selectedDay)
        => range.Weeks.Select(week => new HeatmapWeekRow(week.Days.Select(day => new HeatmapDayRow
        {
            Day = day.Day,
            Intensity = day.Intensity,
            IsFuture = day.IsFuture,
            IsSelected = day.Day == selectedDay,
            Tooltip = $"{day.Date:yyyy-MM-dd dddd} · {(day.IsFuture ? "未到" : DisplayFormat.Duration(day.Seconds))}",
        }).ToList())).ToList();
}

public static class NoteProjections
{
    public static NoteRow Row(StickyNote note, bool historical)
    {
        var meta = historical ? note.DayKey.Replace("-", ".") : note.UpdatedAt.LocalDateTime.ToString("HH:mm") + " 更新";
        return new NoteRow(note.ID, note.Title, Preview(note.Text), meta, note.IsOpen, historical);
    }

    public static List<NoteDayGroup> History(IEnumerable<StickyNote> notes, string today)
        => notes.Where(x => x.DayKey != today)
            .GroupBy(x => x.DayKey)
            .OrderByDescending(g => g.Key, StringComparer.Ordinal)
            .Select(g => new NoteDayGroup(g.Key.Replace("-", "."), g.Count(),
                g.OrderByDescending(x => x.UpdatedAt).Select(x => Row(x, true)).ToList()))
            .ToList();

    /// 与 macOS previewText 一致：首行当标题，剩下的当正文预览；没有正文时退回全文。
    public static string Preview(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return "空白便签";
        var lines = text.Split('\n').Skip(1);
        var body = string.Join("\n", lines).Trim();
        return body.Length == 0 ? trimmed : body;
    }
}

public static class Progressions
{
    public static IEnumerable<AppUsageRow> AppRows(DailySummary summary)
    {
        var total = Math.Max(1, summary.FocusSeconds);
        return summary.Apps.Select(app => new AppUsageRow(app.Name, DisplayFormat.Duration(app.Seconds),
            Math.Clamp(app.Seconds / total, 0, 1)));
    }

    public static IEnumerable<SessionRow> SessionRows(DailySummary summary, AppData data)
    {
        // 与 macOS 的 ProgressTimeline 一致：先按主题归组，组内保持时间顺序。
        foreach (var group in ActivityTopicGroup.Build(summary.Day, summary.Sessions, data))
        {
            var grouped = group.Sessions.Count > 1;
            var first = true;
            foreach (var session in group.Sessions)
            {
                var progress = SessionProgress.Build(session.ID, data, summary.Day);
                if (progress is null) continue;
                var status = session.EndedAt is null ? "进行中" : session.Completed ? "完整番茄" : "提前结束";
                var detail = $"{session.StartedAt.LocalDateTime:HH:mm} · 本日投入 {DisplayFormat.Duration(progress.FocusSeconds)} · {status}";
                var todos = progress.CompletedTodos.Count == 0 ? null : "勾选完成：" + string.Join("、", progress.CompletedTodos.Select(x => x.Text));
                yield return new SessionRow(session.ID, progress.Title, detail, todos, session.Completed, session.EndedAt is null,
                    first && grouped ? group.Title : null,
                    first && grouped ? $"{group.Sessions.Count} 轮 · {DisplayFormat.Duration(group.Seconds)}" : null);
                first = false;
            }
        }
    }

    public static IEnumerable<TodoDayRow> TodoRows(DailySummary summary)
    {
        foreach (var todo in summary.Todos)
        {
            var completedOnDay = todo.CompletionDay == summary.Day;
            var status = todo.CompletionDay is { } day
                ? day == summary.Day ? "当日完成" : $"于 {day} 完成"
                : string.CompareOrdinal(todo.EffectiveScheduledDay, summary.Day) > 0
                    ? $"后续已结转到 {todo.EffectiveScheduledDay}"
                    : "当日未完成";
            yield return new TodoDayRow(todo.ID, todo.Text, completedOnDay, $"原始日期 {todo.LocalDay} · {status}");
        }
    }

    public static ProgressCard? ProgressCardFor(AppData data, Guid? sessionID)
    {
        if (sessionID is not Guid id) return null;
        var progress = SessionProgress.Build(id, data);
        if (progress is null || progress.FocusSeconds <= 0) return null;
        var session = progress.Session;
        var detail = $"投入 {DisplayFormat.Duration(progress.FocusSeconds)}"
            + (progress.CompletedTodos.Count > 0 ? $" · 完成 {progress.CompletedTodos.Count} 项待办" : "");
        var todos = progress.CompletedTodos.Count == 0 ? null : string.Join("、", progress.CompletedTodos.Take(3).Select(x => x.Text));
        return new ProgressCard(id, progress.Title, session.StartedAt.LocalDateTime.ToString("HH:mm"), detail, todos, session.EndedAt is null);
    }
}
