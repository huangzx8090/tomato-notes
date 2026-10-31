using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using TomatoNotes.Core;

var tests = new (string Name, Func<Task> Run)[] {
    ("双端共享 v4 资料契约", () => SharedCompatibilityFixture()),
    ("读取 macOS 参考时间与默认设置", () => CheckAppleDates()),
    ("保存时保留平台扩展字段", () => PreserveUnknownFields()),
    ("读取失败禁止覆盖原始资料", () => ProtectInvalidData()),
    ("备份包含成果图片", () => BackupAssets()),
    ("完整专注进入短休息并记录跨日时长", () => TimerCompletion()),
    ("暂停不计时，提前结束保留投入", () => PauseAndEarlyEnd()),
    ("跨日分配专注与前台 App", () => SplitAcrossDays()),
    ("连续相同 App 分段合并", () => MergeUsage()),
    ("待办按安排日期展示且完成日固定", () => TodoSchedule()),
    ("待办结转候选、批量顺延与撤销", () => TodoCarryoverRules()),
    ("删除待办后恢复原记录", () => TodoDeletionRestore()),
    ("热力图按自然周分页统计真实分段", () => HeatmapRange()),
    ("历史搜索合并同轮目标与成果", () => SearchHistory()),
    ("会话只归集期间完成的待办", () => SessionAttribution()),
    ("OpenAI 兼容模型与总结接口", () => AIContract()),
    ("AI 接口错误不暴露密钥", () => AIError()),
    ("便签活动只记录新增文字", () => NoteActivityRecording()),
    ("待办活动随勾选状态收回", () => TodoActivityRecording()),
    ("暂停或关闭开关时不采集活动", () => ActivityRecordingGuards()),
    ("删除的材料不再进入进展与回顾", () => ExcludedActivityMaterials()),
    ("轮次名称按用户纠正优先", () => RecordedTitlePrecedence()),
    ("自动回顾只在满足条件时触发", () => AutomaticSessionReviewGuards()),
    ("材料摘要只在出现新材料时变化", () => TopicContextDigest()),
    ("AI 主题建议按 macOS 规则校验", () => IdentifyActivityValidation()),
    ("同主题轮次归组统计投入", () => ActivityTopicGrouping()),
    ("活动来源键与 macOS 大写 UUID 一致", () => ActivitySourceKeyInterop()),
    ("活动标题清洗去掉网址与超长文字", () => ActivityPrivacyClean()),
};
var failed = 0;
foreach (var test in tests)
{
    try { await test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failed++; Console.Error.WriteLine($"FAIL {test.Name}\n{ex}"); }
}
Console.WriteLine($"{tests.Length - failed}/{tests.Length} tests passed");
return failed == 0 ? 0 : 1;

static Task SharedCompatibilityFixture()
{
    var directory = new DirectoryInfo(AppContext.BaseDirectory); string? fixture = null;
    while (directory is not null && fixture is null) { var candidate = Path.Combine(directory.FullName, "Compatibility", "data-contract-v4.json"); if (File.Exists(candidate)) fixture = candidate; directory = directory.Parent; }
    if (fixture is null) throw new FileNotFoundException("Shared compatibility fixture not found");
    var data = JsonSerializer.Deserialize<AppData>(File.ReadAllText(fixture), TomatoJson.Options)!;
    Equal(new DateTimeOffset(2001,1,1,0,0,0,TimeSpan.Zero), data.Timer.UpdatedAt); Equal("跨端资料兼容", data.Sessions[0].Goal);
    Equal("2001-01-01", data.Todos[0].CompletionDay); Equal(true, data.Notes[0].Text.Contains("👍")); Equal("A51C4E5B-0AA4-467D-A615-36B6D5327E68.jpg", data.WorkRecords[0].Images[0].FileName);
    var saved = JsonSerializer.Serialize(data, TomatoJson.Options); var root = JsonDocument.Parse(saved).RootElement;
    Equal("must-survive-roundtrip", root.GetProperty("futureRootField").GetString()); Equal("preserve-me", root.GetProperty("settings").GetProperty("focusGuard").GetProperty("macOSOnlyRule").GetString()); Equal(true, root.GetProperty("settings").GetProperty("futureSettingFromEitherPlatform").GetProperty("keep").GetBoolean());
    Equal("keep", root.GetProperty("focusActivities")[0].GetProperty("futureField").GetString());
    return Task.CompletedTask;
}
static Task CheckAppleDates()
{
    var data = JsonSerializer.Deserialize<AppData>("""{"schemaVersion":4,"settings":{},"timer":{"updatedAt":0},"sessions":[{"id":"00000000-0000-0000-0000-000000000001","startedAt":86400,"completed":false}],"intervals":[],"usage":[],"todos":[],"notes":[],"workRecords":[]}""", TomatoJson.Options)!;
    Equal(new DateTimeOffset(2001,1,1,0,0,0,TimeSpan.Zero), data.Timer.UpdatedAt);
    Equal(new DateTimeOffset(2001,1,2,0,0,0,TimeSpan.Zero), data.Sessions[0].StartedAt);
    Equal(25, data.Settings.FocusMinutes); Equal("system", data.Settings.Appearance); Equal(21, data.Settings.Review.Hour);
    return Task.CompletedTask;
}
static Task PreserveUnknownFields()
{
    const string json = """{"schemaVersion":4,"futureFlag":42,"settings":{"appearance":"dark","newMacSetting":true},"timer":{},"sessions":[],"intervals":[],"usage":[],"todos":[],"notes":[],"workRecords":[{"id":"A51C4E5B-0AA4-467D-A615-36B6D5327E67","localDay":"2026-01-01","userText":"成果","images":[{"id":"A51C4E5B-0AA4-467D-A615-36B6D5327E68","name":"result.png","createdAt":0}],"activityTopic":{"title":"保留我"}}]}""";
    var data = JsonSerializer.Deserialize<AppData>(json, TomatoJson.Options)!;
    var saved = JsonSerializer.Serialize(data, TomatoJson.Options);
    Contains("\"futureFlag\": 42", saved); Contains("\"newMacSetting\": true", saved); Contains("\"activityTopic\"", saved); Contains("\"A51C4E5B-0AA4-467D-A615-36B6D5327E67.jpg\"", "\"A51C4E5B-0AA4-467D-A615-36B6D5327E67.jpg\"");
    Equal("A51C4E5B-0AA4-467D-A615-36B6D5327E68.jpg", data.WorkRecords[0].Images[0].FileName);
    return Task.CompletedTask;
}
static Task ProtectInvalidData()
{
    using var dir = new TemporaryDirectory(); File.WriteAllText(Path.Combine(dir.Path, "data.json"), "not json");
    using var repository = new LocalRepository(dir.Path); repository.Load(); Equal(false, repository.CanWrite);
    try { repository.Save(new()); throw new Exception("不应覆盖损坏资料"); } catch (InvalidOperationException) { }
    Equal("not json", File.ReadAllText(Path.Combine(dir.Path, "data.json"))); return Task.CompletedTask;
}
static Task BackupAssets()
{
    using var dir = new TemporaryDirectory(); var repository = new LocalRepository(dir.Path); var data = new AppData(); repository.Save(data);
    Directory.CreateDirectory(repository.AttachmentsPath); File.WriteAllText(Path.Combine(repository.AttachmentsPath, "image.jpg"), "image"); var backup = repository.Backup()!;
    Equal("image", File.ReadAllText(Path.Combine(Path.ChangeExtension(backup, ".assets")!, "Attachments", "image.jpg"))); repository.Dispose(); return Task.CompletedTask;
}
static Task TimerCompletion()
{
    var data = new AppData(); var engine = new TimerEngine(data); var now = new DateTimeOffset(2026,1,1,12,0,0,TimeSpan.Zero);
    engine.Start(now, " 写测试 "); Equal("写测试", data.Sessions[0].Goal); engine.Advance(1499, now.AddSeconds(1499), null, true);
    Equal(TimerPhase.Running, data.Timer.Phase); Equal(true, engine.Advance(1, now.AddSeconds(1500), null, true)); Equal(TimerPhase.Completed, data.Timer.Phase); Equal(TimerStage.ShortBreak, data.Timer.NextStage); Equal(1500, data.Intervals.Sum(x => x.Seconds));
    engine.Start(now.AddSeconds(1501)); Equal(TimerStage.ShortBreak, data.Timer.Stage); Equal(300, data.Timer.RemainingSeconds); return Task.CompletedTask;
}
static Task PauseAndEarlyEnd()
{
    var engine = new TimerEngine(new()); var now = DateTimeOffset.UtcNow; engine.Start(now); engine.Advance(30, now.AddSeconds(30), null, true); engine.Pause("test", now.AddSeconds(30)); Equal(false, engine.Advance(60, now.AddSeconds(90), null, true)); engine.EndEarlyOrSkip(now.AddSeconds(90));
    Equal(TimerPhase.Idle, engine.Timer.Phase); Equal(false, engine.Data.Sessions[0].Completed); Equal(30, engine.Data.Intervals.Sum(x => x.Seconds)); return Task.CompletedTask;
}
static Task SessionAttribution()
{
    var now = DateTimeOffset.UtcNow;
    var day = now.LocalDateTime.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
    var sessionID = Guid.NewGuid();
    var data = new AppData();
    data.Sessions.Add(new FocusSession { ID = sessionID, StartedAt = now, EndedAt = now.AddMinutes(25), EndedLocalDay = day, Completed = true });
    data.Intervals.Add(new FocusInterval { SessionID = sessionID, StartedAt = now, EndedAt = now.AddMinutes(25), LocalDay = day, Seconds = 1500 });
    // 会话期间完成的待办应归集；会话之外完成的不计入
    data.Todos.Add(new TodoItem { Text = "会话内", LocalDay = day, CompletedAt = now.AddMinutes(10) });
    data.Todos.Add(new TodoItem { Text = "会话外", LocalDay = day, CompletedAt = now.AddHours(5) });

    var progress = SessionProgress.Build(sessionID, data, day);
    if (progress is null) throw new InvalidOperationException("会话进度未生成");
    Equal(1500, progress.FocusSeconds);
    Equal(1, progress.CompletedTodos.Count);
    Equal("会话内", progress.CompletedTodos[0].Text);

    // 没有对应会话时不应产出进展卡片
    var missing = SessionProgress.Build(Guid.NewGuid(), data, day);
    Equal(true, missing is null);
    return Task.CompletedTask;
}

static Task SplitAcrossDays()
{
    var engine = new TimerEngine(new()); var start = new DateTimeOffset(DateTime.Today.AddDays(-1).AddHours(23).AddMinutes(59).AddSeconds(59)); engine.Start(start); engine.Advance(2, start.AddSeconds(2), new("编辑器", "win.editor"), true);
    Equal(2, engine.Data.Intervals.Count); Equal(1, engine.Data.Intervals.Sum(x => x.Seconds) - engine.Data.Intervals.Min(x => x.Seconds)); return Task.CompletedTask;
}
static Task MergeUsage()
{
    var engine = new TimerEngine(new()); var now = DateTimeOffset.UtcNow; engine.Start(now); engine.Advance(1, now.AddSeconds(1), new("Chrome", "chrome.exe"), true); engine.Advance(1, now.AddSeconds(2), new("Chrome", "chrome.exe"), true); Equal(1, engine.Data.Usage.Count); Equal(2, engine.Data.Usage[0].Seconds); return Task.CompletedTask;
}
static Task TodoSchedule()
{
    var completed = new DateTimeOffset(2026,1,2,8,0,0,TimeSpan.FromHours(8)); var todo = new TodoItem { Text = "任务", LocalDay = "2026-01-01", ScheduledDays = ["2026-01-01", "2026-01-02"], CompletedAt = completed, CompletedLocalDay = "2026-01-02" };
    Equal(true, todo.IsScheduledOn("2026-01-01")); Equal("2026-01-02", todo.CompletionDay); var summary = DailySummary.Build("2026-01-02", new() { Todos = [todo] }); Equal(1, summary.CompletedTodos); return Task.CompletedTask;
}
static Task TodoCarryoverRules()
{
    var todos = new List<TodoItem>
    {
        new() { Text = "旧任务", LocalDay = "2026-10-20" },
        new() { Text = "更旧", LocalDay = "2026-10-19" },
        new() { Text = "未来", LocalDay = "2026-10-25" },
    };
    Equal("更旧,旧任务", string.Join(",", TodoCarryover.Candidates(todos, "2026-10-23").Select(x => x.Text)));
    var changed = TodoCarryover.Schedule(todos.Select(x => x.ID), "2026-10-23", todos);
    Equal("更旧,旧任务", string.Join(",", changed.Select(id => todos.First(x => x.ID == id).Text)));
    Equal(2, todos.Count(x => x.IsScheduledOn("2026-10-23")));
    Equal(false, todos[2].IsScheduledOn("2026-10-23"));
    Equal(TodoCarryoverUndoResult.Undone, TodoCarryover.UndoSchedule(todos[1].ID, "2026-10-23", todos));
    Equal(false, todos[1].IsScheduledOn("2026-10-23"));
    Equal(true, todos[1].IsScheduledOn("2026-10-19"));
    Equal(TodoCarryoverUndoResult.NotScheduledToday, TodoCarryover.UndoSchedule(todos[1].ID, "2026-10-19", todos));
    return Task.CompletedTask;
}
static Task TodoDeletionRestore()
{
    var todos = new List<TodoItem> { new() { Text = "第一", LocalDay = "2026-10-23" }, new() { Text = "第二", LocalDay = "2026-10-23" } };
    var history = new TodoDeletionHistory();
    Equal(true, history.Remove(todos[0].ID, "2026-10-23", todos));
    Equal("第二", todos.Single().Text);
    Equal("第一", history.RestoreLast(todos)!.Text);
    Equal(2, todos.Count);
    Equal("第一", todos[0].Text);
    return Task.CompletedTask;
}
static Task HeatmapRange()
{
    var today = new DateTime(2026, 10, 27);
    var intervals = new List<FocusInterval>
    {
        new() { LocalDay = "2026-10-27", Seconds = 1800 },
        new() { LocalDay = "2026-10-26", Seconds = 600 },
        new() { LocalDay = "2026-10-01", Seconds = 300 },
    };
    var range = FocusHeatmapRange.Build(intervals, 1, today: today);
    Equal("2026-10-26", range.StartDay);
    Equal("2026-11-01", range.EndDay);
    Equal(2, range.ActiveDays);
    Equal(2400, range.TotalSeconds);
    Equal(1, range.Weeks[0].Days.First(x => x.Day == "2026-10-26").Intensity);
    var previous = FocusHeatmapRange.Build(intervals, 1, 1, today);
    Equal("2026-10-19", previous.StartDay);
    return Task.CompletedTask;
}
static Task SearchHistory()
{
    var id = Guid.NewGuid();
    var data = new AppData();
    data.Sessions.Add(new() { ID = id, Goal = "量子线路", StartedAt = new DateTimeOffset(2026, 10, 20, 9, 0, 0, TimeSpan.Zero) });
    data.Intervals.Add(new() { SessionID = id, LocalDay = "2026-10-20", Seconds = 1500 });
    data.WorkRecords.Add(new() { LocalDay = "2026-10-20", SessionID = id, UserText = "整理量子线路结论", Summary = new() { Content = new() { Outcomes = ["结论可靠"] } } });
    data.Notes.Add(new() { Text = "量子线路笔记", LocalDay = "2026-10-20" });
    var result = new HistorySearchIndex(data).Search("量子 线路",
        new(new HashSet<HistorySearchKind> { HistorySearchKind.Focus, HistorySearchKind.Outcome }, null, null)).Single();
    Equal(HistorySearchKind.Focus, result.Kind);
    Equal("2026-10-20", result.Day);
    Equal(true, result.Excerpt.Contains("用户记录"));
    Equal(true, result.Excerpt.Contains("量子线路"));
    var filtered = new HistorySearchIndex(data).Search("量子", new(new HashSet<HistorySearchKind> { HistorySearchKind.Note }, null, null));
    Equal(1, filtered.Count);
    Equal(HistorySearchKind.Note, filtered[0].Kind);
    return Task.CompletedTask;
}
static async Task AIContract()
{
    var handler = new StubHandler(request => {
        if (request.RequestUri!.AbsolutePath.EndsWith("models")) return Json("""{"data":[{"id":"test-model"}]}""");
        var payload = System.Text.Json.Nodes.JsonNode.Parse(request.Content!.ReadAsStringAsync().Result)!;
        Contains("不要输出 Markdown 代码围栏或其他文字。", payload["messages"]![0]!["content"]!.GetValue<string>());
        Contains("data:image/jpeg;base64,", payload["messages"]![1]!["content"]!.ToJsonString());
        return Json("""{"choices":[{"finish_reason":"stop","message":{"content":"{\"activities\":[\"整理资料\"],\"outcomes\":[],\"nextSteps\":[],\"uncertainties\":[]}"}}]}""");
    });
    using var client = new AIClient(new("custom", "Test", "https://example.test/v1", "test-model"), handler);
    Equal("test-model", (await client.FetchModels("secret")).Single()); var result = await client.Summarize("资料", [(new() { Name = "x" }, [1,2,3])], "secret"); Equal("整理资料", result.Activities.Single());
}
static async Task AIError()
{
    using var client = new AIClient(new("custom", "Test", "https://example.test/v1", "model"), new StubHandler(_ => new(HttpStatusCode.Unauthorized) { Content = new StringContent("do not expose") }));
    try { await client.FetchModels("secret-key"); throw new Exception("预期401"); } catch (InvalidOperationException ex) { Equal(false, ex.Message.Contains("secret-key")); }
}
static HttpResponseMessage Json(string text) => new(HttpStatusCode.OK) { Content = new StringContent(text, Encoding.UTF8, "application/json") };
static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected: {expected}\nActual: {actual}"); }
static void Contains(string expected, string actual) { if (!actual.Contains(expected)) throw new Exception($"Missing: {expected}"); }
static void Missing(string unexpected, string actual) { if (actual.Contains(unexpected)) throw new Exception($"Should not contain: {unexpected}"); }
static async Task Throws<T>(Func<Task> action, string label) where T : Exception
{
    Exception? caught = null;
    try { await action(); } catch (Exception ex) { caught = ex; }
    if (caught is null) throw new Exception($"预期抛出 {typeof(T).Name}：{label}");
    if (caught is not T) throw new Exception($"预期 {typeof(T).Name}，实际 {caught.GetType().Name}：{label}\n{caught.Message}");
}

/// 一轮正在进行的专注，已开启活动记录与 App 明细，便于各条测试直接写材料。
static (AppData Data, Guid SessionID, DateTimeOffset Start, string Day) RecordingFixture(double focusSeconds = 600)
{
    var start = DateTimeOffset.UtcNow.AddMinutes(-30);
    var day = LocalTime.DayKey(start);
    var sessionID = Guid.NewGuid();
    var data = new AppData();
    data.Settings.ActivityRecording.Enabled = true;
    data.Settings.ActivityRecording.NotesEnabled = true;
    data.Settings.ActivityRecording.AppUsageEnabled = true;
    data.Settings.RecordingEnabled = true;
    data.Timer.Stage = TimerStage.Focus;
    data.Timer.Phase = TimerPhase.Running;
    data.Timer.SessionID = sessionID;
    data.Sessions.Add(new FocusSession { ID = sessionID, StartedAt = start });
    data.Intervals.Add(new FocusInterval { SessionID = sessionID, StartedAt = start, EndedAt = start.AddSeconds(focusSeconds), LocalDay = day, Seconds = focusSeconds });
    return (data, sessionID, start, day);
}

static StickyNote WriteNote(AppData data, string baseline, string text, DateTimeOffset now, Guid blockID)
{
    var note = data.Notes.FirstOrDefault(x => x.Text == baseline) ?? new StickyNote { Text = baseline };
    if (!data.Notes.Contains(note)) data.Notes.Add(note);
    note.Text = text;
    ActivityRecorder.RecordNote(note, baseline, now, blockID, data);
    return note;
}

static Task NoteActivityRecording()
{
    var (data, sessionID, start, day) = RecordingFixture();
    var block = Guid.NewGuid();
    var note = WriteNote(data, "标题", "标题\n第一段", start.AddMinutes(2), block);
    Equal(1, data.FocusActivities.Count);
    Equal(ActivityKind.NoteEdited, data.FocusActivities[0].Kind);
    Equal("第一段", data.FocusActivities[0].Title);
    Equal(sessionID, data.FocusActivities[0].SessionID);
    Equal(day, data.FocusActivities[0].LocalDay);

    // 基线是当天第一次看到的文字，所以同一记录块内继续写会把新增行按顺序并到同一条材料上。
    note.Text = "标题\n第一段\n第二段";
    ActivityRecorder.RecordNote(note, "标题", start.AddMinutes(4), block, data);
    Equal(1, data.FocusActivities.Count);
    Equal("第一段\n第二段", data.FocusActivities[0].Detail);
    Equal("第一段", data.FocusActivities[0].Title);
    Equal(start.AddMinutes(4), data.FocusActivities[0].EndedAt);

    // 换一个记录块就是新的一条材料；只删行时没有新增文字，用兜底文案占位，与 macOS 一致。
    note.Text = "标题\n第二段";
    ActivityRecorder.RecordNote(note, "标题\n第一段\n第二段", start.AddMinutes(6), Guid.NewGuid(), data);
    Equal(2, data.FocusActivities.Count);
    Equal("便签文字调整", data.FocusActivities[1].Title);
    Equal("调整了便签文字，未记录新增内容。", data.FocusActivities[1].Detail);
    return Task.CompletedTask;
}

static Task TodoActivityRecording()
{
    var (data, _, start, day) = RecordingFixture();
    var todo = new TodoItem { Text = "整理季度报表", LocalDay = day, ScheduledDays = [day], CompletedAt = start.AddMinutes(5) };
    data.Todos.Add(todo);
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    Equal(1, data.FocusActivities.Count);
    Equal(ActivityKind.TodoCompleted, data.FocusActivities[0].Kind);
    Equal("整理季度报表", data.FocusActivities[0].Title);

    // 取消勾选要把之前的完成记录一起收回，否则材料里会留下已经不成立的成果。
    todo.CompletedAt = null;
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(6), data);
    Equal(0, data.FocusActivities.Count);

    todo.CompletedAt = start.AddMinutes(7);
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(7), data);
    Equal(1, data.FocusActivities.Count);
    Equal(start.AddMinutes(7), data.FocusActivities[0].StartedAt);
    return Task.CompletedTask;
}

static Task ActivityRecordingGuards()
{
    var (data, _, start, _) = RecordingFixture();
    var todo = new TodoItem { Text = "待办", CompletedAt = start.AddMinutes(5) };
    data.Todos.Add(todo);
    var note = new StickyNote { Text = "标题\n新增" };
    data.Notes.Add(note);

    // 暂停时停止采集。
    data.Timer.Phase = TimerPhase.Paused;
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    ActivityRecorder.RecordNote(note, "标题", start.AddMinutes(5), Guid.NewGuid(), data);
    Equal(0, data.FocusActivities.Count);

    // 休息阶段不采集。
    data.Timer.Phase = TimerPhase.Running; data.Timer.Stage = TimerStage.ShortBreak;
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    Equal(0, data.FocusActivities.Count);

    // 总开关与便签开关关掉后同样不采集。
    data.Timer.Stage = TimerStage.Focus;
    data.Settings.ActivityRecording.Enabled = false;
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    Equal(0, data.FocusActivities.Count);
    data.Settings.ActivityRecording.Enabled = true;
    data.Settings.ActivityRecording.NotesEnabled = false;
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    ActivityRecorder.RecordNote(note, "标题", start.AddMinutes(5), Guid.NewGuid(), data);
    Equal(0, data.FocusActivities.Count);
    return Task.CompletedTask;
}

static Task ExcludedActivityMaterials()
{
    var (data, sessionID, start, day) = RecordingFixture();
    var todo = new TodoItem { Text = "会话内完成", LocalDay = day, ScheduledDays = [day], CompletedAt = start.AddMinutes(5), CompletedLocalDay = day };
    data.Todos.Add(todo);
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    Equal(1, SessionProgress.Build(sessionID, data, day)!.CompletedTodos.Count);

    // 用户删掉这条材料后：进展不再归集、回顾不再引用、也不会重新采集回来。
    data.WorkRecords.Add(new WorkRecord { LocalDay = day, SessionID = sessionID, ExcludedActivityKeys = [ActivityRecorder.TodoKey(todo.ID)] });
    Equal(0, SessionProgress.Build(sessionID, data, day)!.CompletedTodos.Count);
    // 排除键挡的是"重新采集"：已经写进去的那条交给读取端过滤，不会再被采集回来。
    data.FocusActivities.Clear();
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(6), data);
    Equal(0, data.FocusActivities.Count);
    Missing("会话内完成", ReviewContextBuilder.Build(WorkScope.ForDay(day), data).Text);
    Missing("会话内完成", ReviewContextBuilder.Build(WorkScope.ForSession(sessionID), data).Text);
    return Task.CompletedTask;
}

static Task RecordedTitlePrecedence()
{
    var (data, sessionID, start, day) = RecordingFixture();
    var todo = new TodoItem { Text = "第一件事", LocalDay = day, ScheduledDays = [day], CompletedAt = start.AddMinutes(5), CompletedLocalDay = day };
    data.Todos.Add(todo);
    var record = new WorkRecord { LocalDay = day, SessionID = sessionID, ActivityTopic = new() { Title = "AI 识别的主题" } };
    data.WorkRecords.Add(record);
    data.Sessions[0].Goal = "本轮目标";

    // 用户纠正 > 本轮目标 > AI 主题 > 本轮第一件事 > 兜底文案。
    Equal("本轮目标", SessionProgress.Build(sessionID, data, day)!.Title);
    record.TitleOverride = "用户改的名称";
    Equal("用户改的名称", SessionProgress.Build(sessionID, data, day)!.Title);
    Equal("用户改的名称", ActivityRecorder.DisplayTitle(data.Sessions[0], data));
    record.TitleOverride = null; data.Sessions[0].Goal = null;
    Equal("AI 识别的主题", SessionProgress.Build(sessionID, data, day)!.Title);
    record.ActivityTopic = null;
    Equal("第一件事", SessionProgress.Build(sessionID, data, day)!.Title);
    todo.CompletedAt = null;
    Equal("一段专心的时间", SessionProgress.Build(sessionID, data, day)!.Title);
    return Task.CompletedTask;
}

static Task AutomaticSessionReviewGuards()
{
    var (data, sessionID, start, day) = RecordingFixture();
    data.Timer.Phase = TimerPhase.Idle; data.Timer.SessionID = null;
    var record = new WorkRecord { LocalDay = day, SessionID = sessionID, AutomaticRecordingUsed = true };
    data.WorkRecords.Add(record);
    data.Settings.Review.AutoSummarizeSessions = false;

    // 还没结束的这一轮不自动整理。
    Equal(false, AutomaticSessionReview.ShouldGenerate(sessionID, data));
    data.Sessions[0].EndedAt = start.AddMinutes(10); data.Sessions[0].Completed = true;
    Equal(true, AutomaticSessionReview.ShouldGenerate(sessionID, data));

    // 投入不足一分钟、已经尝试过、两个开关都关，都不触发。
    data.Intervals[0].Seconds = 30; data.Intervals[0].EndedAt = start.AddSeconds(30);
    Equal(false, AutomaticSessionReview.ShouldGenerate(sessionID, data));
    data.Intervals[0].Seconds = 600; data.Intervals[0].EndedAt = start.AddMinutes(10);
    record.AutoReviewAttemptedAt = DateTimeOffset.UtcNow;
    Equal(false, AutomaticSessionReview.ShouldGenerate(sessionID, data));
    record.AutoReviewAttemptedAt = null;
    data.Settings.ActivityRecording.Enabled = false;
    Equal(false, AutomaticSessionReview.ShouldGenerate(sessionID, data));

    // 没开自动整理，但开了每轮自动总结时仍要触发。
    data.Settings.Review.AutoSummarizeSessions = true;
    Equal(true, AutomaticSessionReview.ShouldGenerate(sessionID, data));

    // 没用过自动记录时，单开活动记录不足以触发。
    data.Settings.Review.AutoSummarizeSessions = false;
    data.Settings.ActivityRecording.Enabled = true;
    record.AutomaticRecordingUsed = false;
    Equal(false, AutomaticSessionReview.ShouldGenerate(sessionID, data));
    return Task.CompletedTask;
}

static Task TopicContextDigest()
{
    var (data, sessionID, start, _) = RecordingFixture();
    var block = Guid.NewGuid();
    WriteNote(data, "标题", "标题\n第一段", start.AddMinutes(2), block);
    var first = ActivityTopicContext.Build(sessionID, data);
    Equal(1, first.EvidenceIDs.Count);

    // 只是停留时长增长不算新材料，避免每 15 秒重发一次请求。
    data.FocusActivities[0].Seconds += 120;
    Equal(first.Digest, ActivityTopicContext.Build(sessionID, data).Digest);

    // 出现新材料后摘要变化。
    WriteNote(data, "标题\n第一段", "标题\n第一段\n第二段", start.AddMinutes(4), block);
    var second = ActivityTopicContext.Build(sessionID, data);
    Equal(true, first.Digest != second.Digest);

    // 关掉便签来源后这些材料不再作为证据；没有证据就不该发请求。
    data.Settings.ActivityRecording.NotesEnabled = false;
    Equal(0, ActivityTopicContext.Build(sessionID, data).EvidenceIDs.Count);
    Equal(false, ActivityTopicPolicy.ShouldIdentify(sessionID, data));
    // 重新打开便签来源后这些材料又成了证据，识别随之恢复。
    data.Settings.ActivityRecording.NotesEnabled = true;
    Equal(true, ActivityTopicPolicy.ShouldIdentify(sessionID, data, final: false));

    // 关掉总开关后连结束时也不再判断。
    data.Settings.ActivityRecording.Enabled = false;
    Equal(false, ActivityTopicPolicy.ShouldIdentify(sessionID, data, final: true));
    return Task.CompletedTask;
}

static async Task IdentifyActivityValidation()
{
    var (data, sessionID, start, _) = RecordingFixture();
    WriteNote(data, "标题", "标题\n整理季度报表", start.AddMinutes(3), Guid.NewGuid());
    var evidence = data.FocusActivities[0].ID;
    var groupID = Guid.NewGuid();
    data.WorkRecords.Add(new WorkRecord { LocalDay = data.Sessions[0].StartedAt.LocalDateTime.ToString("yyyy-MM-dd"), SessionID = Guid.NewGuid(), ActivityTopic = new() { GroupID = groupID, Title = "已有主题" } });
    var context = ActivityTopicContext.Build(sessionID, data);
    Equal(1, context.EvidenceIDs.Count);
    Equal(true, context.CandidateIDs.Contains(groupID));
    // 提示词里的材料 ID 与主题 ID 都用大写，与 macOS 的 uuidString 写法一致。
    Contains(evidence.ToString().ToUpperInvariant(), context.Text);
    Contains(groupID.ToString().ToUpperInvariant(), context.Text);

    var provider = new AIProvider("custom", "Test", "https://example.test/v1", "test-model");
    async Task<ActivityTopicSuggestion> Identify(JsonObject payload)
    {
        using var client = new AIClient(provider, new StubHandler(_ => TopicResponse(payload)));
        return await client.IdentifyActivity(context, "secret");
    }
    static JsonObject Topic(string title, double confidence, JsonArray ids, string? matching = null) => new()
    {
        ["title"] = title, ["confidence"] = confidence, ["evidenceIDs"] = ids,
        ["matchingTopicID"] = matching is null ? null : JsonValue.Create(matching),
    };

    var ok = await Identify(Topic("季度报表整理", .82, new JsonArray(JsonValue.Create(evidence.ToString())), groupID.ToString()));
    Equal("季度报表整理", ok.Title); Equal(.82, ok.Confidence); Equal(evidence, ok.EvidenceIDs.Single()); Equal(groupID, ok.MatchingTopicID);

    // 材料不足时不发请求。
    await Throws<InvalidDataException>(() => new AIClient(provider, new StubHandler(_ => TopicResponse(new JsonObject())))
        .IdentifyActivity(new ActivityTopicContext("{}", "digest", [], []), "secret"), "无证据");
    // 置信度越界、引用不存在的材料、非空标题没有依据、复用不存在的主题，都要判为无效。
    await Throws<InvalidDataException>(() => Identify(Topic("主题", 1.4, new JsonArray(JsonValue.Create(evidence.ToString())))), "置信度越界");
    await Throws<InvalidDataException>(() => Identify(Topic("主题", .9, new JsonArray(JsonValue.Create(Guid.NewGuid().ToString())))), "引用外来材料");
    await Throws<InvalidDataException>(() => Identify(Topic("主题", .9, new JsonArray())), "非空标题无依据");
    await Throws<InvalidDataException>(() => Identify(Topic("主题", .9, new JsonArray(JsonValue.Create(evidence.ToString())), Guid.NewGuid().ToString())), "复用未知主题");
    await Throws<InvalidDataException>(() => Identify(Topic(new string('长', 61), .9, new JsonArray(JsonValue.Create(evidence.ToString())))), "标题超长");
    // 空标题表示材料不足，属于合法返回，由调用方决定不落库。
    var blank = await Identify(Topic("", .2, new JsonArray()));
    Equal("", blank.Title); Equal(.2, blank.Confidence);
}

static HttpResponseMessage TopicResponse(JsonObject payload) => Json(new JsonObject
{
    ["choices"] = new JsonArray(new JsonObject
    {
        ["finish_reason"] = "stop",
        ["message"] = new JsonObject { ["content"] = payload.ToJsonString() },
    }),
}.ToJsonString());

static Task ActivityTopicGrouping()
{
    var (data, _, start, day) = RecordingFixture();
    data.Timer.Phase = TimerPhase.Idle; data.Timer.SessionID = null;
    // 这条只看新建的三轮，先清掉夹具里那轮进行中的会话。
    data.Sessions.Clear(); data.Intervals.Clear();
    var groupID = Guid.NewGuid();
    var first = NewSession(data, start, day, 600, null);
    var second = NewSession(data, start.AddHours(1), day, 300, null);
    var third = NewSession(data, start.AddHours(2), day, 900, "复习软考");
    data.WorkRecords.Add(new WorkRecord { LocalDay = day, SessionID = first, ActivityTopic = new() { GroupID = groupID, Title = "季度报表" } });
    data.WorkRecords.Add(new WorkRecord { LocalDay = day, SessionID = second, ActivityTopic = new() { GroupID = groupID, Title = "季度报表" } });
    data.WorkRecords.Add(new WorkRecord { LocalDay = day, SessionID = third, TitleOverride = "用户改过的名称" });

    var groups = ActivityTopicGroup.Build(day, data.Sessions, data);
    Equal(2, groups.Count);
    Equal("季度报表", groups[0].Title);
    Equal(2, groups[0].Sessions.Count);
    Equal(900, groups[0].Seconds);
    // 用户改过名的那一轮独立成组，不会被并回 AI 主题里。
    Equal("用户改过的名称", groups[1].Title);
    Equal(1, groups[1].Sessions.Count);
    Equal(900, groups[1].Seconds);

    // 本轮目标优先于 AI 主题，所以设了目标的同一主题轮次不会并组，与 macOS displayTitle 的顺序一致。
    var fourth = NewSession(data, start.AddHours(3), day, 300, "写季度报表");
    data.WorkRecords.Add(new WorkRecord { LocalDay = day, SessionID = fourth, ActivityTopic = new() { GroupID = groupID, Title = "季度报表" } });
    var split = ActivityTopicGroup.Build(day, data.Sessions, data);
    Equal(3, split.Count);
    Equal(2, split[0].Sessions.Count);
    Equal("写季度报表", split[2].Title);
    return Task.CompletedTask;
}

static Guid NewSession(AppData data, DateTimeOffset start, string day, double seconds, string? goal)
{
    var id = Guid.NewGuid();
    data.Sessions.Add(new FocusSession { ID = id, StartedAt = start, EndedAt = start.AddSeconds(seconds), EndedLocalDay = day, Completed = true, Goal = goal });
    data.Intervals.Add(new FocusInterval { SessionID = id, StartedAt = start, EndedAt = start.AddSeconds(seconds), LocalDay = day, Seconds = seconds });
    return id;
}

static Task ActivitySourceKeyInterop()
{
    var todoID = Guid.Parse("a51c4e5b-0aa4-467d-a615-36b6d5327e67");
    var noteID = Guid.Parse("b51c4e5b-0aa4-467d-a615-36b6d5327e68");
    // macOS 的 uuidString 是大写，两端读写同一份资料时排除键必须对得上。
    Equal("todoCompleted|A51C4E5B-0AA4-467D-A615-36B6D5327E67", ActivityRecorder.TodoKey(todoID));
    Equal("noteEdited|B51C4E5B-0AA4-467D-A615-36B6D5327E68", ActivityRecorder.NoteKey(noteID));

    var (data, sessionID, start, day) = RecordingFixture();
    var todo = new TodoItem { ID = todoID, Text = "跨端材料", LocalDay = day, ScheduledDays = [day], CompletedAt = start.AddMinutes(5), CompletedLocalDay = day };
    data.Todos.Add(todo);
    ActivityRecorder.RecordTodo(todo, start.AddMinutes(5), data);
    Equal("todoCompleted|A51C4E5B-0AA4-467D-A615-36B6D5327E67", data.FocusActivities[0].SourceKey);

    // macOS 写下的 chromePage 材料在 Windows 端要能读出来、显示出来并原样保存。
    var chrome = new FocusActivity
    {
        SessionID = sessionID, Kind = ActivityKind.ChromePage, Title = "数据库规范化", Site = "example.com",
        StartedAt = start.AddMinutes(6), EndedAt = start.AddMinutes(9), LocalDay = day, Seconds = 180,
    };
    data.FocusActivities.Add(chrome);
    // macOS 的 chromePage 键前缀是 chrome，Windows 必须写同一个键才能对上排除记录。
    Equal("chrome|example.com|数据库规范化", data.FocusActivities[1].SourceKey);
    Equal("浏览：数据库规范化", chrome.Label);
    Equal(2, ActivityRecorder.Activities(sessionID, data).Count);
    var roundTrip = JsonSerializer.Deserialize<AppData>(JsonSerializer.Serialize(data, TomatoJson.Options), TomatoJson.Options)!;
    Equal("数据库规范化", roundTrip.FocusActivities.Single(x => x.Kind == ActivityKind.ChromePage).Title);
    return Task.CompletedTask;
}

static Task ActivityPrivacyClean()
{
    // 有的网页直接把完整网址当标题，清洗后不能留下路径与查询参数。
    var cleaned = ActivityPrivacy.Clean("参考 https://example.com/docs/guide?token=abc#top 这一页", 60);
    Contains("example.com", cleaned);
    Missing("token=abc", cleaned);
    Missing("/docs/guide", cleaned);
    // 光秃秃的协议头不算网址，原样保留，避免把用户写的普通文字吞掉。
    Equal("not a url 见 http://", ActivityPrivacy.Clean("not a url 见 http://", 60));
    // 能匹配但解析不出主机的地址退回占位符，绝不把整段地址写进材料。
    Equal("[网址]", ActivityPrivacy.Clean("http://:80/x", 60));
    Equal("见 example.com", ActivityPrivacy.Clean("见 https://example.com/a/b?c=1", 60));
    Equal(10, ActivityPrivacy.Clean(new string('长', 40), 10).Length);
    Equal("", ActivityPrivacy.Clean("   ", 60));
    return Task.CompletedTask;
}

sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(response(request)); }
sealed class TemporaryDirectory : IDisposable { public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "TomatoTests-" + Guid.NewGuid().ToString("N")); public TemporaryDirectory() => Directory.CreateDirectory(Path); public void Dispose() { try { Directory.Delete(Path, true); } catch { } } }
