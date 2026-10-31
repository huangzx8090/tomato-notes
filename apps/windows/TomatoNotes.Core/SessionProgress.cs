namespace TomatoNotes.Core;

/// 从原始事实即时生成一轮专注的进展，不把计划或 App 停留时长当成已经完成的成果。
/// 与 macOS 的 TomatoCore/SessionProgress.swift 对应。
public sealed class SessionProgress
{
    public required FocusSession Session { get; init; }
    public required double FocusSeconds { get; init; }
    public required List<TodoItem> CompletedTodos { get; init; }
    public required List<AppTotal> Apps { get; init; }
    /// 已经落到记录上的名称：用户纠正优先，其次是本轮目标，最后是 AI 识别的主题。
    public required string? RecordedTitle { get; init; }

    public string Title
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(RecordedTitle)) return RecordedTitle!;
            if (!string.IsNullOrWhiteSpace(Session.Goal)) return Session.Goal!;
            return CompletedTodos.Count > 0 ? CompletedTodos[0].Text : "一段专心的时间";
        }
    }

    public static SessionProgress? Build(Guid sessionID, AppData data, string? day = null)
    {
        var session = data.Sessions.FirstOrDefault(x => x.ID == sessionID);
        if (session is null) return null;
        var record = ReviewContextBuilder.Record(WorkScope.ForSession(sessionID), data);
        var intervals = data.Intervals.Where(x => x.SessionID == sessionID && (day is null || x.LocalDay == day)).ToList();
        // 暂停或休息时勾选的任务不能自动归入这一轮：只有落在本轮投入区间内的完成事件才算。
        // 用户删掉过的材料也不再归入，否则「已删除」只是界面效果。
        var todos = data.Todos
            .Where(todo => !(record?.ExcludedActivityKeys?.Contains(ActivityRecorder.TodoKey(todo.ID)) == true)
                && todo.CompletedAt.HasValue
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
        var recorded = !string.IsNullOrWhiteSpace(record?.TitleOverride) ? record!.TitleOverride
            : !string.IsNullOrWhiteSpace(session.Goal) ? session.Goal
            : record?.ActivityTopic?.Title;
        return new SessionProgress { Session = session, FocusSeconds = intervals.Sum(x => x.Seconds), CompletedTodos = todos, Apps = apps, RecordedTitle = recorded };
    }
}

public static class AutomaticSessionReview
{
    /// 只用于刚结束后排队的轮次；不扫描历史，也不自动重试失败的请求。
    public static bool ShouldGenerate(Guid sessionID, AppData data)
    {
        var record = ReviewContextBuilder.Record(WorkScope.ForSession(sessionID), data);
        if (!(data.Settings.Review.AutoSummarizeSessions || (data.Settings.ActivityRecording.Enabled && record?.AutomaticRecordingUsed == true))) return false;
        var progress = SessionProgress.Build(sessionID, data);
        if (progress is null || progress.Session.EndedAt is null || progress.FocusSeconds < 60) return false;
        if (record?.AutoReviewAttemptedAt is not null) return false;
        return record?.Summary?.ContextDigest != ReviewContextBuilder.Build(WorkScope.ForSession(sessionID), data).Digest;
    }
}
