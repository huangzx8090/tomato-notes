using System.Net;
using System.Text;
using System.Text.Json;
using TomatoNotes.Core;

var tests = new (string Name, Func<Task> Run)[] {
    ("读取 macOS 参考时间与默认设置", () => CheckAppleDates()),
    ("保存时保留平台扩展字段", () => PreserveUnknownFields()),
    ("读取失败禁止覆盖原始资料", () => ProtectInvalidData()),
    ("备份包含成果图片", () => BackupAssets()),
    ("完整专注进入短休息并记录跨日时长", () => TimerCompletion()),
    ("暂停不计时，提前结束保留投入", () => PauseAndEarlyEnd()),
    ("跨日分配专注与前台 App", () => SplitAcrossDays()),
    ("连续相同 App 分段合并", () => MergeUsage()),
    ("待办按安排日期展示且完成日固定", () => TodoSchedule()),
    ("OpenAI 兼容模型与总结接口", () => AIContract()),
    ("AI 接口错误不暴露密钥", () => AIError()),
};
var failed = 0;
foreach (var test in tests)
{
    try { await test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failed++; Console.Error.WriteLine($"FAIL {test.Name}\n{ex}"); }
}
Console.WriteLine($"{tests.Length - failed}/{tests.Length} tests passed");
return failed == 0 ? 0 : 1;

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

sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(response(request)); }
sealed class TemporaryDirectory : IDisposable { public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "TomatoTests-" + Guid.NewGuid().ToString("N")); public TemporaryDirectory() => Directory.CreateDirectory(Path); public void Dispose() { try { Directory.Delete(Path, true); } catch { } } }
