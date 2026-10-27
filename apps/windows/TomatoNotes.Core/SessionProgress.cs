namespace TomatoNotes.Core;

/// 从原始事实即时生成一轮专注的进展，不把计划或 App 停留时长当成已经完成的成果。
/// 与 macOS 的 TomatoCore/SessionProgress.swift 对应；Windows 端没有活动记录与主题识别，
/// 因此不含 RecordedTitle，也没有 ExcludedActivityKeys 过滤。
public sealed class SessionProgress
{
    public required FocusSession Session { get; init; }
    public required double FocusSeconds { get; init; }
    public required List<TodoItem> CompletedTodos { get; init; }
    public required List<AppTotal> Apps { get; init; }

    public string Title
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Session.Goal)) return Session.Goal!;
            return CompletedTodos.Count > 0 ? CompletedTodos[0].Text : "一段专心的时间";
        }
    }

    public static SessionProgress? Build(Guid sessionID, AppData data, string? day = null)
    {
        var session = data.Sessions.FirstOrDefault(x => x.ID == sessionID);
        if (session is null) return null;
        var intervals = data.Intervals.Where(x => x.SessionID == sessionID && (day is null || x.LocalDay == day)).ToList();
        // 暂停或休息时勾选的任务不能自动归入这一轮：只有落在本轮投入区间内的完成事件才算。
        var todos = data.Todos
            .Where(todo => todo.CompletedAt.HasValue
                && (day is null || todo.CompletionDay == day)
                && intervals.Any(x => todo.CompletedAt >= x.StartedAt && todo.CompletedAt < x.EndedAt))
            .OrderBy(todo => todo.CompletedAt)
            .ToList();
        var apps = data.Usage
            .Where(x => x.SessionID == sessionID && x.Kind == UsageKind.App && (day is null || x.LocalDay == day))
            .GroupBy(x => x.BundleID ?? "unknown")
            .Select(g => new AppTotal(g.Key, g.First().AppName ?? "未知应用", g.Sum(x => x.Seconds)))
            .OrderByDescending(x => x.Seconds)
            .ThenBy(x => x.BundleID, StringComparer.Ordinal)
            .ToList();
        return new SessionProgress { Session = session, FocusSeconds = intervals.Sum(x => x.Seconds), CompletedTodos = todos, Apps = apps };
    }
}
