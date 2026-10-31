using System.Security.Cryptography;
using System.Runtime.Serialization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace TomatoNotes.Core;

/// 与 macOS 的 TomatoCore/ActivityRecording.swift 对应。
/// Windows 只采集便签变更与完成待办：Chrome 页面读取依赖 AppleScript，不移植，
/// 但 chromePage 记录仍要能读取、展示并随资料保存，保证两端互通。
public sealed class ActivityRecordingSettings : JsonModel
{
    [JsonPropertyName("enabled")] public bool Enabled { get; set; }
    [JsonPropertyName("chromeEnabled")] public bool ChromeEnabled { get; set; } = true;
    [JsonPropertyName("notesEnabled")] public bool NotesEnabled { get; set; } = true;
    [JsonPropertyName("appUsageEnabled")] public bool AppUsageEnabled { get; set; } = true;
    [OnDeserialized] internal void Repair(StreamingContext _) { }
}

/// 活动类型的 JSON 取值，与 macOS 的 FocusActivity.Kind 原始值一致。
public static class ActivityKind
{
    public const string ChromePage = "chromePage";
    public const string NoteEdited = "noteEdited";
    public const string TodoCompleted = "todoCompleted";
}

public sealed class FocusActivity : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("sessionID")] public Guid SessionID { get; set; }
    [JsonPropertyName("kind")] public string Kind { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("site")] public string? Site { get; set; }
    [JsonPropertyName("detail")] public string? Detail { get; set; }
    [JsonPropertyName("sourceID")] public Guid? SourceID { get; set; }
    [JsonPropertyName("startedAt")] public DateTimeOffset StartedAt { get; set; }
    [JsonPropertyName("endedAt")] public DateTimeOffset EndedAt { get; set; }
    [JsonPropertyName("localDay")] public string LocalDay { get; set; } = "";
    [JsonPropertyName("seconds")] public double Seconds { get; set; }
    [JsonPropertyName("focusIntervalID")] public Guid? FocusIntervalID { get; set; }
    [JsonPropertyName("recordingBlockID")] public Guid? RecordingBlockID { get; set; }

    public string Label => Kind switch
    {
        ActivityKind.ChromePage => "浏览：" + Title,
        ActivityKind.NoteEdited => "便签变更：" + Title,
        ActivityKind.TodoCompleted => "勾选完成：" + Title,
        _ => Title,
    };

    /// 删除一条材料时用这个键把本轮同源材料一起停记，避免下一轮又采集回来。
    /// 键里的 UUID 用大写：macOS 的 uuidString 就是大写，两端读写同一份资料时必须对得上。
    public string SourceKey => Kind == ActivityKind.ChromePage
        ? $"chrome|{Site}|{Title}"
        : ActivityRecorder.SourceKey(Kind, SourceID);
}

public static partial class ActivityPrivacy
{
    /// 有的网页直接把完整网址当标题，避免借标题保存查询参数或路径。
    public static string Clean(string text, int limit)
    {
        var value = UrlRegex().Replace(text ?? "", match =>
            Uri.TryCreate(match.Value, UriKind.Absolute, out var url) && url.Host.Length > 0 ? url.Host : "[网址]");
        value = value.Trim();
        return value.Length <= limit ? value : value[..limit];
    }

    [GeneratedRegex(@"https?://[^\s<>]+", RegexOptions.IgnoreCase)]
    private static partial Regex UrlRegex();
}

public static class ActivityRecorder
{
    public static string SourceKey(string kind, Guid? sourceID) => $"{kind}|{(sourceID is Guid id ? id.ToString().ToUpperInvariant() : "")}";
    public static string TodoKey(Guid todoID) => SourceKey(ActivityKind.TodoCompleted, todoID);
    public static string NoteKey(Guid noteID) => SourceKey(ActivityKind.NoteEdited, noteID);

    public static bool IsRecording(AppData data) => data.Settings.ActivityRecording.Enabled
        && data.Timer.Stage == TimerStage.Focus && data.Timer.Phase == TimerPhase.Running && data.Timer.SessionID.HasValue;

    public static List<FocusActivity> Activities(Guid sessionID, AppData data, string? day = null)
        => data.FocusActivities.Where(x => x.SessionID == sessionID && (day is null || x.LocalDay == day)).OrderBy(x => x.StartedAt).ToList();

    /// 调用方须先把新文字写进 note，再传入改动前的基线文本。
    public static void RecordNote(StickyNote note, string previousText, DateTimeOffset now, Guid? blockID, AppData data)
    {
        if (!IsRecording(data) || !data.Settings.ActivityRecording.NotesEnabled || data.Timer.SessionID is not Guid sessionID) return;
        if (Excluded(NoteKey(note.ID), sessionID, data)) return;
        var inserted = InsertedLines(previousText.Split('\n'), note.Text.Split('\n'));
        var detail = ActivityPrivacy.Clean(string.Join("\n", inserted), 1200);
        var title = ActivityPrivacy.Clean(detail.Split('\n')[0], 60);
        var intervalID = data.Intervals.LastOrDefault(x => x.SessionID == sessionID)?.ID;
        var day = LocalTime.DayKey(now);
        var existing = data.FocusActivities.LastOrDefault(x => x.SessionID == sessionID && x.Kind == ActivityKind.NoteEdited
            && x.SourceID == note.ID && x.LocalDay == day && x.FocusIntervalID == intervalID && x.RecordingBlockID == blockID);
        if (note.Text == previousText && existing is null) return;
        var nextTitle = title.Length == 0 ? "便签文字调整" : title;
        var nextDetail = detail.Length == 0 ? "调整了便签文字，未记录新增内容。" : detail;
        if (existing is not null) { existing.Title = nextTitle; existing.Detail = nextDetail; existing.EndedAt = now; }
        else data.FocusActivities.Add(new()
        {
            SessionID = sessionID, Kind = ActivityKind.NoteEdited, Title = nextTitle, Detail = nextDetail, SourceID = note.ID,
            StartedAt = now, EndedAt = now, LocalDay = day, FocusIntervalID = intervalID, RecordingBlockID = blockID,
        });
    }

    public static void RecordTodo(TodoItem todo, DateTimeOffset now, AppData data)
    {
        if (!IsRecording(data) || !data.Settings.ActivityRecording.NotesEnabled || data.Timer.SessionID is not Guid sessionID) return;
        if (Excluded(TodoKey(todo.ID), sessionID, data)) return;
        // 取消勾选要把之前的完成记录一起收回，否则材料里会留下已经不成立的成果。
        data.FocusActivities.RemoveAll(x => x.SessionID == sessionID && x.Kind == ActivityKind.TodoCompleted && x.SourceID == todo.ID);
        if (todo.IsCompleted) data.FocusActivities.Add(new()
        {
            SessionID = sessionID, Kind = ActivityKind.TodoCompleted, Title = ActivityPrivacy.Clean(todo.Text, 300),
            SourceID = todo.ID, StartedAt = now, EndedAt = now, LocalDay = LocalTime.DayKey(now),
        });
    }

    public static string DisplayTitle(FocusSession session, AppData data)
    {
        var record = ReviewContextBuilder.Record(WorkScope.ForSession(session.ID), data);
        return record?.TitleOverride ?? (!string.IsNullOrWhiteSpace(session.Goal) ? session.Goal! : record?.ActivityTopic?.Title ?? "一段专心的时间");
    }

    private static bool Excluded(string key, Guid sessionID, AppData data)
        => ReviewContextBuilder.Record(WorkScope.ForSession(sessionID), data)?.ExcludedActivityKeys?.Contains(key) == true;

    /// 只取新增行，保留顺序与重复；等价 macOS 的 difference(from:) 里的 insert 分支。
    internal static List<string> InsertedLines(string[] previous, string[] current)
    {
        // 超长便签不逐格比对，退回按出现次数取差集，避免 O(n*m) 的内存开销。
        if ((long)previous.Length * current.Length > 4_000_000)
        {
            var remaining = previous.GroupBy(x => x).ToDictionary(g => g.Key, g => g.Count());
            var fallback = new List<string>();
            foreach (var line in current)
            {
                if (remaining.TryGetValue(line, out var count) && count > 0) remaining[line] = count - 1;
                else fallback.Add(line);
            }
            return fallback;
        }
        var common = new int[previous.Length + 1, current.Length + 1];
        for (var i = previous.Length - 1; i >= 0; i--)
            for (var j = current.Length - 1; j >= 0; j--)
                common[i, j] = previous[i] == current[j] ? common[i + 1, j + 1] + 1 : Math.Max(common[i + 1, j], common[i, j + 1]);
        var inserted = new List<string>();
        int x = 0, y = 0;
        while (x < previous.Length && y < current.Length)
        {
            if (previous[x] == current[y]) { x++; y++; }
            else if (common[x + 1, y] >= common[x, y + 1]) x++;
            else inserted.Add(current[y++]);
        }
        while (y < current.Length) inserted.Add(current[y++]);
        return inserted;
    }
}

public sealed record ActivityTopicContext(string Text, string Digest, HashSet<Guid> EvidenceIDs, HashSet<Guid> CandidateIDs)
{
    public static ActivityTopicContext Build(Guid sessionID, AppData data)
    {
        var settings = data.Settings.ActivityRecording;
        var evidence = ActivityRecorder.Activities(sessionID, data)
            .Where(x => x.Kind == ActivityKind.ChromePage ? settings.ChromeEnabled && x.Seconds >= 15 : settings.NotesEnabled)
            .TakeLast(60).ToList();
        var candidates = new JsonArray(); var seen = new HashSet<Guid>();
        foreach (var record in data.WorkRecords.AsEnumerable().Reverse().Where(x => x.SessionID != sessionID))
        {
            if (record.ActivityTopic is not { } topic || !seen.Add(topic.GroupID)) continue;
            candidates.Add(new JsonObject { ["id"] = Upper(topic.GroupID), ["名称"] = record.TitleOverride ?? topic.Title, ["用户纠正"] = record.TitleOverride is null ? "否" : "是" });
            if (candidates.Count >= 15) break;
        }
        var current = ReviewContextBuilder.Record(WorkScope.ForSession(sessionID), data)?.ActivityTopic;
        if (current is not null && seen.Add(current.GroupID)) candidates.Add(new JsonObject { ["id"] = Upper(current.GroupID), ["名称"] = current.Title, ["用户纠正"] = "否" });
        var facts = new JsonObject
        {
            ["用户设定的目标（计划，不代表实际活动）"] = data.Sessions.FirstOrDefault(x => x.ID == sessionID)?.Goal ?? "",
            ["本轮已观察到的材料"] = new JsonArray(evidence.Select(x => (JsonNode)new JsonObject
            {
                ["id"] = Upper(x.ID), ["类型"] = x.Kind, ["标题"] = x.Title,
                ["网站"] = x.Site ?? "", ["变更文字"] = x.Detail ?? "", ["前台秒数"] = Math.Round(x.Seconds),
            }).ToArray()),
            ["已有主题（仅供归类命名，不能当作本轮证据）"] = candidates,
            ["前台App（只说明工具，不是主题依据）"] = settings.AppUsageEnabled && data.Settings.RecordingEnabled
                ? new JsonArray((SessionProgress.Build(sessionID, data)?.Apps ?? []).Select(x => (JsonNode)new JsonObject { ["App"] = x.Name, ["秒数"] = Math.Round(x.Seconds) }).ToArray())
                : [],
        };
        // 时长增长不算新材料；只在出现新材料或便签再次变化时重新判断。
        // 摘要里的 UUID 用大写：macOS 的 uuidString 就是大写，两端写进同一条记录的摘要才互相认得。
        var semantic = string.Join("\n", evidence.Select(x => $"{Upper(x.ID)}|{x.Title}|{x.Detail}"));
        return new(facts.ToJsonString(), Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(semantic))).ToLowerInvariant(),
            evidence.Select(x => x.ID).ToHashSet(), seen);
    }

    private static string Upper(Guid value) => value.ToString().ToUpperInvariant();
}

public static class ActivityTopicPolicy
{
    public static bool ShouldIdentify(Guid sessionID, AppData data, bool final = false)
    {
        if (!data.Settings.ActivityRecording.Enabled) return false;
        var progress = SessionProgress.Build(sessionID, data);
        if (progress is null || progress.FocusSeconds < (final ? 60 : 120)) return false;
        var record = ReviewContextBuilder.Record(WorkScope.ForSession(sessionID), data);
        if (record?.TitleOverride is not null || (record?.TopicAttemptCount ?? 0) >= (final ? 5 : 4)) return false;
        var context = ActivityTopicContext.Build(sessionID, data);
        if (context.EvidenceIDs.Count == 0 || record?.TopicAttemptDigest == context.Digest) return false;
        var materials = data.FocusActivities.Where(x => context.EvidenceIDs.Contains(x.ID)).ToList();
        if (!materials.Any(x => x.Kind != ActivityKind.ChromePage) && materials.Sum(x => x.Seconds) < 45) return false;
        if (final) return progress.Session.EndedAt is not null && record?.FinalTopicAttempted != true;
        if (data.Timer.SessionID != sessionID || !ActivityRecorder.IsRecording(data)) return false;
        return record?.TopicAttemptFocusSeconds is null || progress.FocusSeconds - record.TopicAttemptFocusSeconds >= 300;
    }
}

/// 一天里按主题归组的轮次，对应 macOS 的 ActivityTopicGroup。
/// 同一 AI 主题分组或同名记录并成一组；没有主题时按轮次各自成组，顺序仍是时间顺序。
public sealed class ActivityTopicGroup
{
    public required string Key { get; init; }
    public required string Title { get; init; }
    public double Seconds { get; set; }
    public List<FocusSession> Sessions { get; } = [];

    public static List<ActivityTopicGroup> Build(string day, IEnumerable<FocusSession> sessions, AppData data)
    {
        var groups = new List<ActivityTopicGroup>();
        foreach (var session in sessions)
        {
            var record = ReviewContextBuilder.Record(WorkScope.ForSession(session.ID), data);
            var title = ActivityRecorder.DisplayTitle(session, data);
            // 组 ID 用大写：与 macOS 的 uuidString 写法一致，两端读同一份资料时归组结果相同。
            var groupID = record?.ActivityTopic?.GroupID.ToString().ToUpperInvariant() ?? "session-" + session.ID.ToString().ToUpperInvariant();
            var key = groupID + "|" + title;
            var seconds = SessionProgress.Build(session.ID, data, day)?.FocusSeconds ?? 0;
            var existing = groups.FirstOrDefault(x => x.Key == key);
            if (existing is null) groups.Add(new ActivityTopicGroup { Key = key, Title = title, Seconds = seconds, Sessions = { session } });
            else { existing.Seconds += seconds; existing.Sessions.Add(session); }
        }
        return groups;
    }
}
