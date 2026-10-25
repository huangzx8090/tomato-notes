using System.Globalization;
using System.Runtime.Serialization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Nodes;

namespace TomatoNotes.Core;

/// <summary>JSON field names and defaults mirror the macOS v4 data format.
/// Extension data preserves fields belonging to newer or platform-specific macOS features.</summary>
public abstract class JsonModel
{
    [JsonExtensionData] public Dictionary<string, JsonElement>? Extra { get; set; }
}

public sealed class AppData : JsonModel
{
    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; set; } = 4;
    [JsonPropertyName("settings")] public AppSettings Settings { get; set; } = new();
    [JsonPropertyName("timer")] public TimerSnapshot Timer { get; set; } = new();
    [JsonPropertyName("sessions")] public List<FocusSession> Sessions { get; set; } = [];
    [JsonPropertyName("intervals")] public List<FocusInterval> Intervals { get; set; } = [];
    [JsonPropertyName("usage")] public List<AppUsageSegment> Usage { get; set; } = [];
    [JsonPropertyName("todos")] public List<TodoItem> Todos { get; set; } = [];
    [JsonPropertyName("notes")] public List<StickyNote> Notes { get; set; } = [];
    [JsonPropertyName("workRecords")] public List<WorkRecord> WorkRecords { get; set; } = [];
    [JsonPropertyName("focusActivities")] public List<JsonObject> FocusActivities { get; set; } = [];
    [JsonPropertyName("lastReviewAttemptDay")] public string? LastReviewAttemptDay { get; set; }
    [JsonPropertyName("lastReviewError")] public string? LastReviewError { get; set; }
    [OnDeserialized] internal void Repair(StreamingContext _) { Settings ??= new(); Timer ??= new(); Sessions ??= []; Intervals ??= []; Usage ??= []; Todos ??= []; Notes ??= []; WorkRecords ??= []; FocusActivities ??= []; }
}

public sealed class AppSettings : JsonModel
{
    [JsonPropertyName("focusMinutes")] public int FocusMinutes { get; set; } = 25;
    [JsonPropertyName("shortBreakMinutes")] public int ShortBreakMinutes { get; set; } = 5;
    [JsonPropertyName("longBreakMinutes")] public int LongBreakMinutes { get; set; } = 15;
    [JsonPropertyName("longBreakEvery")] public int LongBreakEvery { get; set; } = 4;
    [JsonPropertyName("soundEnabled")] public bool SoundEnabled { get; set; } = true;
    [JsonPropertyName("notificationsEnabled")] public bool NotificationsEnabled { get; set; } = true;
    [JsonPropertyName("recordingEnabled")] public bool RecordingEnabled { get; set; } = true;
    [JsonPropertyName("allowClamshellWithExternalDisplay")] public bool AllowClamshellWithExternalDisplay { get; set; } = true;
    [JsonPropertyName("showDockIcon")] public bool ShowDockIcon { get; set; }
    [JsonPropertyName("glassControlsEnabled")] public bool GlassControlsEnabled { get; set; } = true;
    [JsonPropertyName("appearance")] public string Appearance { get; set; } = "system";
    [JsonPropertyName("focusGuard")] public JsonObject FocusGuard { get; set; } = [];
    [JsonPropertyName("review")] public ReviewSettings Review { get; set; } = new();
    [JsonPropertyName("ai")] public AISettings AI { get; set; } = new();
    [JsonPropertyName("activityRecording")] public JsonObject ActivityRecording { get; set; } = [];
    [JsonPropertyName("timerHotkey")] public Hotkey TimerHotkey { get; set; } = new() { Letter = "P" };
    [JsonPropertyName("todoHotkey")] public Hotkey TodoHotkey { get; set; } = new() { Letter = "T" };
    [JsonPropertyName("noteHotkey")] public Hotkey NoteHotkey { get; set; } = new() { Letter = "N" };
    [OnDeserialized] internal void Repair(StreamingContext _) { Review ??= new(); AI ??= new(); FocusGuard ??= []; ActivityRecording ??= []; TimerHotkey ??= new() { Letter = "P" }; TodoHotkey ??= new() { Letter = "T" }; NoteHotkey ??= new() { Letter = "N" }; }
    public double Duration(string stage) => (stage == TimerStage.ShortBreak ? ShortBreakMinutes : stage == TimerStage.LongBreak ? LongBreakMinutes : FocusMinutes) * 60;
}

public sealed class ReviewSettings : JsonModel
{
    [JsonPropertyName("scheduleEnabled")] public bool ScheduleEnabled { get; set; }
    [JsonPropertyName("autoSummarizeSessions")] public bool AutoSummarizeSessions { get; set; }
    [JsonPropertyName("hour")] public int Hour { get; set; } = 21;
    [JsonPropertyName("minute")] public int Minute { get; set; } = 30;
}

public sealed class AISettings : JsonModel
{
    [JsonPropertyName("providerID")] public string ProviderID { get; set; } = "deepseek";
    [JsonPropertyName("customBaseURL")] public string CustomBaseURL { get; set; } = "";
    [JsonPropertyName("modelOverride")] public string ModelOverride { get; set; } = "";
}

public sealed class Hotkey : JsonModel
{
    [JsonPropertyName("enabled")] public bool Enabled { get; set; } = true;
    [JsonPropertyName("letter")] public string Letter { get; set; } = "P";
    [JsonPropertyName("modifier")] public string Modifier { get; set; } = "controlOption";
}

public sealed class TimerSnapshot : JsonModel
{
    [JsonPropertyName("stage")] public string Stage { get; set; } = TimerStage.Focus;
    [JsonPropertyName("phase")] public string Phase { get; set; } = TimerPhase.Idle;
    [JsonPropertyName("nextStage")] public string? NextStage { get; set; }
    [JsonPropertyName("targetSeconds")] public double TargetSeconds { get; set; } = 1500;
    [JsonPropertyName("remainingSeconds")] public double RemainingSeconds { get; set; } = 1500;
    [JsonPropertyName("completedInSet")] public int CompletedInSet { get; set; }
    [JsonPropertyName("sessionID")] public Guid? SessionID { get; set; }
    [JsonPropertyName("pauseReason")] public string? PauseReason { get; set; }
    [JsonPropertyName("updatedAt")] public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class FocusSession : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("startedAt")] public DateTimeOffset StartedAt { get; set; }
    [JsonPropertyName("endedAt")] public DateTimeOffset? EndedAt { get; set; }
    [JsonPropertyName("endedLocalDay")] public string? EndedLocalDay { get; set; }
    [JsonPropertyName("endTimeZoneID")] public string? EndTimeZoneID { get; set; }
    [JsonPropertyName("completed")] public bool Completed { get; set; }
    [JsonPropertyName("endReason")] public string? EndReason { get; set; }
    [JsonPropertyName("goal")] public string? Goal { get; set; }
    [JsonPropertyName("whitelistedBundleIDs")] public List<string>? WhitelistedBundleIDs { get; set; }
    [JsonPropertyName("outsideWhitelistSeconds")] public double? OutsideWhitelistSeconds { get; set; }
}

public sealed class FocusInterval : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("sessionID")] public Guid SessionID { get; set; }
    [JsonPropertyName("startedAt")] public DateTimeOffset StartedAt { get; set; }
    [JsonPropertyName("endedAt")] public DateTimeOffset EndedAt { get; set; }
    [JsonPropertyName("localDay")] public string LocalDay { get; set; } = "";
    [JsonPropertyName("timeZoneID")] public string TimeZoneID { get; set; } = "";
    [JsonPropertyName("seconds")] public double Seconds { get; set; }
}

public sealed class AppUsageSegment : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("sessionID")] public Guid SessionID { get; set; }
    [JsonPropertyName("kind")] public string Kind { get; set; } = UsageKind.Unattributed;
    [JsonPropertyName("appName")] public string? AppName { get; set; }
    [JsonPropertyName("bundleID")] public string? BundleID { get; set; }
    [JsonPropertyName("startedAt")] public DateTimeOffset StartedAt { get; set; }
    [JsonPropertyName("endedAt")] public DateTimeOffset EndedAt { get; set; }
    [JsonPropertyName("localDay")] public string LocalDay { get; set; } = "";
    [JsonPropertyName("timeZoneID")] public string TimeZoneID { get; set; } = "";
    [JsonPropertyName("seconds")] public double Seconds { get; set; }
}

public sealed class TodoItem : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("text")] public string Text { get; set; } = "";
    [JsonPropertyName("localDay")] public string LocalDay { get; set; } = "";
    [JsonPropertyName("createdAt")] public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    [JsonPropertyName("completedAt")] public DateTimeOffset? CompletedAt { get; set; }
    [JsonPropertyName("scheduledDays")] public List<string> ScheduledDays { get; set; } = [];
    [JsonPropertyName("completedLocalDay")] public string? CompletedLocalDay { get; set; }
    [JsonIgnore] public bool IsCompleted => CompletedAt.HasValue;
    [OnDeserialized] internal void Repair(StreamingContext _) { ScheduledDays = ScheduledDays?.Where(x => !string.IsNullOrEmpty(x)).Distinct().ToList() ?? []; if (!ScheduledDays.Contains(LocalDay)) ScheduledDays.Insert(0, LocalDay); if (!CompletedAt.HasValue) CompletedLocalDay = null; else CompletedLocalDay ??= LocalTime.DayKey(CompletedAt.Value); }
    public bool IsScheduledOn(string day) => ScheduledDays.Count == 0 ? LocalDay == day : ScheduledDays.Contains(day);
    public string? CompletionDay => CompletedAt.HasValue ? CompletedLocalDay ?? LocalTime.DayKey(CompletedAt.Value) : null;
    public string EffectiveScheduledDay => ScheduledDays.Count == 0 ? LocalDay : ScheduledDays.Max() ?? LocalDay;
}

public sealed class StickyNote : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("text")] public string Text { get; set; } = "";
    [JsonPropertyName("createdAt")] public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    [JsonPropertyName("updatedAt")] public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    [JsonPropertyName("x")] public double? X { get; set; }
    [JsonPropertyName("y")] public double? Y { get; set; }
    [JsonPropertyName("width")] public double Width { get; set; } = 320;
    [JsonPropertyName("height")] public double Height { get; set; } = 360;
    [JsonPropertyName("isOpen")] public bool IsOpen { get; set; } = true;
    [JsonPropertyName("localDay")] public string? LocalDay { get; set; }
    [JsonPropertyName("continuedFromNoteID")] public Guid? ContinuedFromNoteID { get; set; }
    [JsonIgnore] public string DayKey => LocalDay ?? LocalTime.DayKey(CreatedAt);
    [JsonIgnore] public string Title { get { var line = Text.Split('\n')[0].Trim(); return string.IsNullOrEmpty(line) ? "新便签" : line[..Math.Min(24, line.Length)]; } }
}

public sealed class WorkRecord : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("localDay")] public string LocalDay { get; set; } = "";
    [JsonPropertyName("sessionID")] public Guid? SessionID { get; set; }
    [JsonPropertyName("userText")] public string UserText { get; set; } = "";
    [JsonPropertyName("images")] public List<WorkImage> Images { get; set; } = [];
    [JsonPropertyName("summary")] public AISummary? Summary { get; set; }
    [JsonPropertyName("autoReviewAttemptedAt")] public DateTimeOffset? AutoReviewAttemptedAt { get; set; }
    [JsonPropertyName("updatedAt")] public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    [OnDeserialized] internal void Repair(StreamingContext _) { Images ??= []; }
}

public sealed class WorkImage : JsonModel
{
    [JsonPropertyName("id")] public Guid ID { get; set; } = Guid.NewGuid();
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("createdAt")] public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    [JsonIgnore] public string FileName => $"{ID.ToString().ToUpperInvariant()}.jpg";
}

public sealed class AISummary : JsonModel
{
    [JsonPropertyName("content")] public WorkSummary Content { get; set; } = new();
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("generatedAt")] public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.UtcNow;
    [JsonPropertyName("contextDigest")] public string ContextDigest { get; set; } = "";
    [JsonPropertyName("imageIDs")] public List<Guid> ImageIDs { get; set; } = [];
}

public sealed class WorkSummary : JsonModel
{
    [JsonPropertyName("activities")] public List<string> Activities { get; set; } = [];
    [JsonPropertyName("outcomes")] public List<string> Outcomes { get; set; } = [];
    [JsonPropertyName("nextSteps")] public List<string> NextSteps { get; set; } = [];
    [JsonPropertyName("uncertainties")] public List<string> Uncertainties { get; set; } = [];
    public string Markdown => string.Join("\n\n", new[] { ("做了什么", Activities), ("取得的成果", Outcomes), ("待继续", NextSteps), ("待确认", Uncertainties) }.Where(x => x.Item2.Count > 0).Select(x => $"## {x.Item1}\n" + string.Join("\n", x.Item2.Select(y => $"- {y}"))));
}

public static class TimerStage { public const string Focus = "focus", ShortBreak = "shortBreak", LongBreak = "longBreak"; public static string Label(string? stage) => stage switch { ShortBreak => "短休息", LongBreak => "长休息", _ => "专注" }; }
public static class TimerPhase { public const string Idle = "idle", Running = "running", Paused = "paused", Completed = "completed"; }
public static class UsageKind { public const string App = "app", Unattributed = "unattributed", Disabled = "disabled"; }
public record AppIdentity(string Name, string BundleID);
public record WorkScope(string? Day, Guid? SessionID) { public static WorkScope ForDay(string day) => new(day, null); public static WorkScope ForSession(Guid id) => new(null, id); public string Key => SessionID.HasValue ? $"session-{SessionID}" : $"day-{Day}"; }

public static class LocalTime
{
    public static string DayKey(DateTimeOffset date) => date.LocalDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    public static string TimeZoneID => TimeZoneInfo.Local.Id;
    public static IEnumerable<(DateTimeOffset Start, DateTimeOffset End, string Day, double Seconds)> Split(DateTimeOffset start, DateTimeOffset end, double seconds)
    {
        if (end <= start || seconds <= 0) yield break;
        var cursor = start; var wall = (end - start).TotalSeconds;
        while (cursor < end)
        {
            var local = cursor.LocalDateTime;
            var boundary = new DateTimeOffset(local.Date.AddDays(1), TimeZoneInfo.Local.GetUtcOffset(local.Date.AddDays(1)));
            if (boundary > end) boundary = end;
            yield return (cursor, boundary, DayKey(cursor), seconds * (boundary - cursor).TotalSeconds / wall);
            cursor = boundary;
        }
    }
}

public sealed class DailySummary
{
    public required string Day { get; init; }
    public required double FocusSeconds { get; init; }
    public required int CompletedSessions { get; init; }
    public required int EarlySessions { get; init; }
    public required List<TodoItem> Todos { get; init; }
    public required List<AppTotal> Apps { get; init; }
    public required List<FocusSession> Sessions { get; init; }
    public int CompletedTodos => Todos.Count(x => x.CompletionDay == Day);
    public static DailySummary Build(string day, AppData data)
    {
        var ids = data.Intervals.Where(x => x.LocalDay == day).Select(x => x.SessionID).ToHashSet();
        return new() { Day = day, FocusSeconds = data.Intervals.Where(x => x.LocalDay == day).Sum(x => x.Seconds),
            CompletedSessions = data.Sessions.Count(x => x.Completed && x.EndedAt.HasValue && (x.EndedLocalDay ?? LocalTime.DayKey(x.EndedAt.Value)) == day),
            EarlySessions = data.Sessions.Count(x => !x.Completed && x.EndedAt.HasValue && (x.EndedLocalDay ?? LocalTime.DayKey(x.EndedAt.Value)) == day),
            Todos = data.Todos.Where(x => x.IsScheduledOn(day)).OrderBy(x => x.CreatedAt).ToList(), Apps = data.Usage.Where(x => x.LocalDay == day && x.Kind == UsageKind.App).GroupBy(x => x.BundleID ?? "unknown").Select(g => new AppTotal(g.Key, g.Last().AppName ?? "未知应用", g.Sum(x => x.Seconds))).OrderByDescending(x => x.Seconds).ToList(),
            Sessions = data.Sessions.Where(x => x.EndedLocalDay == day || ids.Contains(x.ID)).OrderByDescending(x => x.StartedAt).ToList() };
    }
}
public record AppTotal(string BundleID, string Name, double Seconds);
public static class DisplayFormat
{
    public static string Duration(double seconds) => seconds < 60 ? $"{Math.Round(seconds)} 秒" : seconds < 3600 ? $"{Math.Floor(seconds / 60)} 分钟" : $"{Math.Floor(seconds / 3600)} 小时 {Math.Floor(seconds % 3600 / 60)} 分钟";
}
