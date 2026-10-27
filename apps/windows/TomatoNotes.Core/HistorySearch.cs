namespace TomatoNotes.Core;

public enum HistorySearchKind { Todo, Note, Focus, Outcome }
public enum HistorySearchSource { UserRecord, AiSummary }

public enum HistorySearchTargetKind { Todo, Note, Session, Work }
public sealed record HistorySearchTarget(HistorySearchTargetKind Kind, Guid? ID, string? Day)
{
    public static HistorySearchTarget Todo(Guid id) => new(HistorySearchTargetKind.Todo, id, null);
    public static HistorySearchTarget Note(Guid id) => new(HistorySearchTargetKind.Note, id, null);
    public static HistorySearchTarget Session(Guid id) => new(HistorySearchTargetKind.Session, id, null);
    public static HistorySearchTarget Work(WorkScope scope) => scope.SessionID is Guid id
        ? new(HistorySearchTargetKind.Work, id, null)
        : new(HistorySearchTargetKind.Work, null, scope.Day);
    public WorkScope Scope => Kind == HistorySearchTargetKind.Work
        ? (ID is Guid session ? WorkScope.ForSession(session) : WorkScope.ForDay(Day ?? ""))
        : new(null, ID);
}

public sealed record HistorySearchFilters(IReadOnlySet<HistorySearchKind> Kinds, string? FromDay, string? ThroughDay)
{
    public static HistorySearchFilters All() => new(Enum.GetValues<HistorySearchKind>().ToHashSet(), null, null);
    public bool Contains(HistorySearchKind kind) => Kinds.Contains(kind);
    public bool Allows(string day) => (FromDay is null || string.CompareOrdinal(day, FromDay) >= 0)
        && (ThroughDay is null || string.CompareOrdinal(day, ThroughDay) <= 0);
}

public sealed record HistorySearchResult(
    string ID, HistorySearchTarget Target, HistorySearchKind Kind, string Day, string Title,
    string Excerpt, string SourceLabel);

/// 仅从用户可见的历史文字建立快照；计时状态、活动采样、图片和配置都不进入索引。
public sealed class HistorySearchIndex
{
    private sealed record Document(HistorySearchKind Kind, string Day, HistorySearchSource Source, string Text);
    private sealed record Group(
        string ID, HistorySearchTarget DefaultTarget, HistorySearchTarget? OutcomeTarget,
        string Title, List<Document> Documents);

    private readonly List<Group> groups;

    public HistorySearchIndex(AppData data)
    {
        var builders = new Dictionary<string, (HistorySearchTarget DefaultTarget, HistorySearchTarget? OutcomeTarget, string Title, List<Document> Documents)>(StringComparer.Ordinal);

        void Append(string groupID, HistorySearchTarget defaultTarget, HistorySearchTarget? outcomeTarget,
                    string title, Document document)
        {
            if (!builders.TryGetValue(groupID, out var group))
                group = (defaultTarget, outcomeTarget, title, []);
            if (string.IsNullOrWhiteSpace(group.Title) && !string.IsNullOrWhiteSpace(title)) group.Title = title;
            if (group.OutcomeTarget is null) group.OutcomeTarget = outcomeTarget;
            group.Documents.Add(document);
            builders[groupID] = group;
        }

        foreach (var todo in data.Todos.Where(x => !string.IsNullOrWhiteSpace(x.Text)))
            Append("todo:" + todo.ID.ToString().ToLowerInvariant(), HistorySearchTarget.Todo(todo.ID), null,
                Title(todo.Text, "待办"), new(HistorySearchKind.Todo, todo.LocalDay, HistorySearchSource.UserRecord, todo.Text));

        foreach (var note in data.Notes.Where(x => !string.IsNullOrWhiteSpace(x.Text)))
            Append("note:" + note.ID.ToString().ToLowerInvariant(), HistorySearchTarget.Note(note.ID), null,
                note.Title, new(HistorySearchKind.Note, note.DayKey, HistorySearchSource.UserRecord, note.Text));

        var sessions = data.Sessions.ToDictionary(x => x.ID, x => x);
        var firstDays = data.Intervals.GroupBy(x => x.SessionID)
            .ToDictionary(g => g.Key, g => g.OrderBy(x => x.StartedAt).ThenBy(x => x.LocalDay, StringComparer.Ordinal).First().LocalDay);
        foreach (var session in data.Sessions.Where(x => !string.IsNullOrWhiteSpace(x.Goal)))
        {
            var day = firstDays.GetValueOrDefault(session.ID, LocalTime.DayKey(session.StartedAt));
            Append("session:" + session.ID.ToString().ToLowerInvariant(), HistorySearchTarget.Session(session.ID),
                HistorySearchTarget.Work(WorkScope.ForSession(session.ID)), Title(session.Goal!, "专注目标"),
                new(HistorySearchKind.Focus, day, HistorySearchSource.UserRecord, session.Goal!));
        }

        foreach (var record in data.WorkRecords)
        {
            var session = record.SessionID is Guid id && sessions.TryGetValue(id, out var value) ? value : null;
            var groupID = session is null ? "work-day:" + record.ID.ToString().ToLowerInvariant() : "session:" + session.ID.ToString().ToLowerInvariant();
            var scope = session is null ? WorkScope.ForDay(record.LocalDay) : WorkScope.ForSession(session.ID);
            var fallback = session is null ? "每日成果" : Title(session.Goal ?? "", "本轮成果");
            var title = session is not null && !string.IsNullOrWhiteSpace(session.Goal) ? Title(session.Goal, fallback)
                : !string.IsNullOrWhiteSpace(record.UserText) ? Title(record.UserText, fallback) : fallback;
            if (!string.IsNullOrWhiteSpace(record.UserText))
                Append(groupID, HistorySearchTarget.Work(scope), HistorySearchTarget.Work(scope), title,
                    new(HistorySearchKind.Outcome, record.LocalDay, HistorySearchSource.UserRecord, record.UserText));
            var summary = record.Summary?.Content.Markdown.Trim();
            if (!string.IsNullOrWhiteSpace(summary))
                Append(groupID, HistorySearchTarget.Work(scope), HistorySearchTarget.Work(scope), title,
                    new(HistorySearchKind.Outcome, record.LocalDay, HistorySearchSource.AiSummary, summary));
        }

        groups = builders.Select(x => new Group(x.Key, x.Value.DefaultTarget, x.Value.OutcomeTarget, x.Value.Title, x.Value.Documents))
            .OrderBy(x => x.ID, StringComparer.Ordinal).ToList();
    }

    public List<HistorySearchResult> Search(string query, HistorySearchFilters? filters = null, int limit = 50)
    {
        filters ??= HistorySearchFilters.All();
        var terms = query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray();
        if (terms.Length == 0 || filters.Kinds.Count == 0 || limit <= 0) return [];

        var results = new List<HistorySearchResult>();
        foreach (var group in groups)
        {
            var eligible = group.Documents.Where(x => filters.Contains(x.Kind) && filters.Allows(x.Day)).ToList();
            if (eligible.Count == 0) continue;
            if (!terms.All(term => eligible.Any(x => Contains(term, x.Text)))) continue;

            var matched = eligible.Where(x => terms.Any(term => Contains(term, x.Text))).ToList();
            var focusDays = matched.Where(x => x.Kind == HistorySearchKind.Focus).Select(x => x.Day).ToList();
            var outcomeDays = matched.Where(x => x.Kind == HistorySearchKind.Outcome).Select(x => x.Day).ToList();
            var day = (focusDays.Count > 0 ? focusDays.Min(StringComparer.Ordinal)
                : outcomeDays.Count > 0 ? outcomeDays.Max(StringComparer.Ordinal)
                : matched.Select(x => x.Day).DefaultIfEmpty("").Max(StringComparer.Ordinal)) ?? "";
            var excerpts = matched.Select(x => (x.Source, x.Day, Excerpt(x.Text, terms)))
                .Where(x => x.Item3 is not null)
                .Select(x => (x.Source, x.Day, Excerpt: x.Item3!)).ToList();
            var sourceLabel = string.Join("、", excerpts.Select(x => Label(x.Source)).Distinct());
            var kind = matched.Any(x => x.Kind == HistorySearchKind.Focus) ? HistorySearchKind.Focus
                : matched.FirstOrDefault()?.Kind ?? HistorySearchKind.Outcome;
            var target = matched.Any(x => x.Kind == HistorySearchKind.Outcome) ? group.OutcomeTarget ?? group.DefaultTarget : group.DefaultTarget;
            results.Add(new(group.ID, target, kind, day, group.Title, CombinedExcerpt(excerpts, day), sourceLabel));
        }

        return results.OrderByDescending(x => x.Day, StringComparer.Ordinal)
            .ThenBy(x => x.ID, StringComparer.Ordinal).Take(limit).ToList();
    }

    private static bool Contains(string term, string text) =>
        text.Contains(term, StringComparison.OrdinalIgnoreCase);

    private static string Title(string text, string fallback)
    {
        var line = text.Split('\n')[0].Trim();
        return line.Length == 0 ? fallback : line.Length <= 64 ? line : line[..63] + "…";
    }

    private static string? Excerpt(string text, string[] terms)
    {
        var compact = System.Text.RegularExpressions.Regex.Replace(text, @"\s+", " ").Trim();
        if (compact.Length == 0) return null;
        var ranges = new List<(int Start, int End)>();
        foreach (var term in terms)
        {
            var index = compact.IndexOf(term, StringComparison.OrdinalIgnoreCase);
            if (index < 0) continue;
            ranges.Add((Math.Max(0, index - 52), Math.Min(compact.Length, index + term.Length + 88)));
        }
        if (ranges.Count == 0) return null;
        ranges.Sort((x, y) => x.Start.CompareTo(y.Start));
        var merged = new List<(int Start, int End)>();
        foreach (var range in ranges)
        {
            if (merged.Count > 0 && range.Start <= merged[^1].End)
                merged[^1] = (merged[^1].Start, Math.Max(merged[^1].End, range.End));
            else if (merged.Count < 3) merged.Add(range);
        }
        return string.Join(" … ", merged.Select(x =>
            (x.Start == 0 ? "" : "…") + compact[x.Start..x.End].Trim() + (x.End == compact.Length ? "" : "…")));
    }

    private static string CombinedExcerpt(List<(HistorySearchSource Source, string Day, string Excerpt)> fragments, string day)
    {
        var parts = new List<string>();
        foreach (var source in new[] { HistorySearchSource.UserRecord, HistorySearchSource.AiSummary })
        {
            var snippets = fragments.Where(x => x.Source == source)
                .Select(x => (x.Day == day ? "" : $"（{x.Day}）") + x.Excerpt)
                .Distinct().ToList();
            if (snippets.Count > 0) parts.Add(Label(source) + "：" + string.Join("；", snippets));
        }
        return string.Join("\n", parts);
    }

    private static string Label(HistorySearchSource source) => source == HistorySearchSource.UserRecord ? "用户记录" : "AI 总结";
}
