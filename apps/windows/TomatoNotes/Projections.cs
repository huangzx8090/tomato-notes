using TomatoNotes.Core;

namespace TomatoNotes.Windows;

/// 今日页「专注时使用的 App」一行：名称、时长文本，以及相对当日专注总时长的占比。
public sealed record AppUsageRow(string Name, string Duration, double Ratio);

/// 时间线里的一轮专注。Windows 端没有活动记录与主题归组，
/// 因此按轮次平铺，标题取目标或本轮勾选完成的第一件事。
public sealed record SessionRow(Guid ID, string Title, string Detail, string? Todos, bool Completed, bool InProgress);

/// 当天待办一行，用于今日页的回顾卡片。
public sealed record TodoDayRow(Guid ID, string Text, bool CompletedOnDay, string Detail);

/// 专注页顶部的「这一轮，留下了进展」卡片。
public sealed record ProgressCard(Guid ID, string Title, string Time, string Detail, string? Todos, bool InProgress);

/// 便签列表里的一张卡片。
public sealed record NoteRow(Guid ID, string Title, string Preview, string Meta, bool IsOpen, bool Historical);

/// 历史便签按天分组，对应 macOS 的 NoteDayGroup。
public sealed record NoteDayGroup(string DayLabel, int Count, List<NoteRow> Notes);

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
        foreach (var session in summary.Sessions)
        {
            var progress = SessionProgress.Build(session.ID, data, summary.Day);
            if (progress is null) continue;
            var status = session.EndedAt is null ? "进行中" : session.Completed ? "完整番茄" : "提前结束";
            var detail = $"{session.StartedAt.LocalDateTime:HH:mm} · 本日投入 {DisplayFormat.Duration(progress.FocusSeconds)} · {status}";
            var todos = progress.CompletedTodos.Count == 0 ? null : "勾选完成：" + string.Join("、", progress.CompletedTodos.Select(x => x.Text));
            yield return new SessionRow(session.ID, progress.Title, detail, todos, session.Completed, session.EndedAt is null);
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
