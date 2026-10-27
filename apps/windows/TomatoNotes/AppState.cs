using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

public sealed class AppState : ObservableObject, IDisposable
{
    private static readonly CultureInfo DayLabelCulture = CultureInfo.GetCultureInfo("zh-CN");
    public LocalRepository Repository { get; }
    public AppData Data { get; private set; }
    private readonly TimerEngine engine;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Stopwatch clock = new();
    private TimeSpan? lastTick;
    private DateTime lastSaved = DateTime.UtcNow;
    private bool locked;
    private int currentTab;
    private string selectedDay = LocalTime.DayKey(DateTimeOffset.Now);
    private string goal = "", feedback = "", aiStatus = "", newTodo = "";
    private DailySummary summary;
    private AIClient ai;
    private readonly Dictionary<Guid, NoteWindow> notes = [];
    private readonly Dictionary<string, WorkWindow> workWindows = [];
    private readonly TodoDeletionHistory deletedTodos = new();
    private readonly List<CarryoverRow> carryoverRows = [];
    private FocusHeatmapRange heatmapRange = FocusHeatmapRange.Build(Array.Empty<FocusInterval>(), 13);
    private readonly HashSet<string> generating = [];
    private CancellationTokenSource lifetime = new();
    public event Action<string, string, bool, bool>? NotificationRequested;
    public ObservableCollection<string> Models { get; } = [];
    public bool CanWrite => Repository.CanWrite;
    public bool IsQuitting { get; private set; }
    public string? LoadError => Repository.LoadError;
    public bool BusyAI { get; private set; }
    public string CurrentProviderID => Data.Settings.AI.ProviderID;
    public AIProvider Provider => AIProviders.Resolve(Data.Settings.AI);
    public bool HasAPIKey => CredentialStore.IsConfigured(Provider.ID);
    public string Remaining { get { var seconds = (int)Math.Ceiling(Math.Max(0, Data.Timer.RemainingSeconds)); return $"{seconds / 60:00}:{seconds % 60:00}"; } }
    public string StatusText => Data.Timer.Phase switch { TimerPhase.Idle => "待开始", TimerPhase.Running => Data.Timer.Stage == TimerStage.Focus ? "正在专注" : "正在" + TimerStage.Label(Data.Timer.Stage), TimerPhase.Paused => Data.Timer.PauseReason ?? "已暂停", _ => TimerStage.Label(Data.Timer.Stage) + "完成" };
    public string PrimaryAction => Data.Timer.Phase switch { TimerPhase.Idle => "开始专注", TimerPhase.Running => "暂停", TimerPhase.Paused => "继续", _ => "开始" + TimerStage.Label(Data.Timer.NextStage ?? "下一轮") };
    public string TimerCaption => Data.Timer.Phase switch { TimerPhase.Idle => "留一点时间，专心做一件事。", TimerPhase.Running => Data.Timer.Stage == TimerStage.Focus ? "慢慢来，把注意力放在眼前。" : "离开屏幕，给自己一点空白。", TimerPhase.Paused => "刚才已暂停，准备好后继续。", _ => Data.Timer.NextStage == TimerStage.Focus ? "休息结束了，准备好再开始。" : "这一轮完成了，休息一下吧。" };
    public bool CanEndEarly => Data.Timer.Phase is TimerPhase.Running or TimerPhase.Paused;
    public bool CanSkipBreak => Data.Timer.Phase == TimerPhase.Completed && Data.Timer.NextStage is not null and not TimerStage.Focus;
    public string EndEarlyLabel => Data.Timer.Stage == TimerStage.Focus ? "提前结束这一轮" : "跳过剩余休息";
    public string TodayKey => LocalTime.DayKey(DateTimeOffset.Now);
    public int TodayMinutes => (int)(DailySummary.Build(TodayKey, Data).FocusSeconds / 60);
    public int TodayCompleted => DailySummary.Build(TodayKey, Data).CompletedSessions;
    public IEnumerable<TodoItem> TodayTodos => Data.Todos.Where(x => x.IsScheduledOn(TodayKey)).OrderBy(x => x.CreatedAt);
    public IEnumerable<StickyNote> VisibleNotes => Data.Notes.Where(x => x.DayKey == TodayKey).OrderByDescending(x => x.UpdatedAt);
    public IEnumerable<StickyNote> HistoryNotes => Data.Notes.Where(x => x.DayKey != TodayKey).OrderByDescending(x => x.UpdatedAt);
    public string StorageLabel => Repository.IsSharedLibrary ? "本机共用资料" : "独立测试资料";
    public string DataPath => Repository.FilePath;
    public TodoItem? LastDeleted => deletedTodos.LastDeleted;
    public IEnumerable<CarryoverRow> CarryoverRows => carryoverRows;
    public bool HasCarryoverRows => carryoverRows.Count > 0;
    public string CarryoverCountLabel => $"共 {carryoverRows.Count} 件未完成旧待办";

    // —— 今日页常驻的紧凑热力图：与 macOS FocusHeatmapCompactView 一致，只统计真实专注分段 ——
    public IReadOnlyList<HeatmapWeekRow> HeatmapWeeks { get; private set; } = [];
    public string HeatmapSummaryLabel => $"{DisplayFormat.Duration(heatmapRange.TotalSeconds)} · 有记录 {heatmapRange.ActiveDays} 天";
    public string HeatmapRangeLabel => $"{heatmapRange.StartDay} — {heatmapRange.EndDay}";
    public bool HasHeatmapRecords => heatmapRange.ActiveDays > 0;
    public int CurrentTab { get => currentTab; set { if (Set(ref currentTab, value)) { if (value == 2) RefreshHistory(); Changed(nameof(IsFocusTab)); Changed(nameof(IsTodoTab)); Changed(nameof(IsTodayTab)); Changed(nameof(IsNotesTab)); Changed(nameof(IsSettingsTab)); } } }
    public bool IsFocusTab => CurrentTab == 0; public bool IsTodoTab => CurrentTab == 1; public bool IsTodayTab => CurrentTab == 2; public bool IsNotesTab => CurrentTab == 3; public bool IsSettingsTab => CurrentTab == 4;

    // —— 专注页：状态点、本组进度胶囊与进展卡片 ——
    public bool IsFocusStage => Data.Timer.Stage == TimerStage.Focus;
    public bool IsRunning => Data.Timer.Phase == TimerPhase.Running;
    public int CompletedInSet => Data.Timer.CompletedInSet;
    public int LongBreakEvery => Math.Max(1, Data.Settings.LongBreakEvery);
    public string SetLabel => $"本组 {CompletedInSet} / {LongBreakEvery} 轮";
    public IEnumerable<bool> RoundDots => Enumerable.Range(0, LongBreakEvery).Select(index => index < CompletedInSet);
    public bool HasRoundDots => LongBreakEvery > 1;
    public Wpf.Ui.Controls.SymbolRegular PrimarySymbol => IsRunning ? Wpf.Ui.Controls.SymbolRegular.Pause24 : Wpf.Ui.Controls.SymbolRegular.Play24;
    /// 与 macOS 一致：只有未开始或休息结束待开始时才能改本轮目标，进行中只展示已定下的目标。
    public bool CanEditGoal => (Data.Timer.Phase == TimerPhase.Idle && Data.Timer.Stage == TimerStage.Focus)
        || (Data.Timer.Phase == TimerPhase.Completed && Data.Timer.NextStage == TimerStage.Focus);
    public string CurrentSessionGoal => Data.Timer.SessionID is Guid sessionID
        ? Data.Sessions.FirstOrDefault(x => x.ID == sessionID)?.Goal ?? "" : "";
    public bool HasCurrentSessionGoal => !string.IsNullOrWhiteSpace(CurrentSessionGoal) && !CanEditGoal;
    private ProgressCard? currentProgress;
    public ProgressCard? CurrentProgress => currentProgress;
    public bool HasCurrentProgress => currentProgress is not null;

    // —— 顶栏与今日页 ——
    public string HeaderDate => DateTime.Now.ToString("MM-dd", CultureInfo.InvariantCulture);
    public bool IsToday => SelectedDay == TodayKey;
    public string SelectedDayLabel => DateTime.TryParse(SelectedDay, out var day)
        ? day.ToString("M 月 d 日 dddd", DayLabelCulture) : SelectedDay;
    public bool CanMoveNext => DateTime.TryParse(SelectedDay, out var day) && day.Date.AddDays(1) <= DateTime.Today;
    public int SummaryMinutes => (int)(Summary.FocusSeconds / 60);
    public int SummaryCompletedSessions => Summary.CompletedSessions;
    public string AIStatusLabel => HasAPIKey ? "已配置" : "可选";
    public string SummarySentence => Summary.Sentence;
    public int SummaryEarlySessions => Summary.EarlySessions;
    public bool HasEarlySessions => Summary.EarlySessions > 0;
    public string EarlySessionsLabel => $"另有 {Summary.EarlySessions} 轮提前结束，投入时长已计入。";
    public int SummaryCompletedTodos => Summary.CompletedTodos;
    public int SummaryTodoCount => Summary.Todos.Count;
    public bool HasSummaryTodos => Summary.Todos.Count > 0;
    public bool HasSummarySessions => Summary.Sessions.Count > 0;
    public string DayProgressTitle => IsToday ? "今天留下的进展" : "这一天留下的进展";
    public bool HasApps => Summary.Apps.Count > 0;
    public bool ShowEmptyApps => !HasApps && Summary.FocusSeconds == 0;
    public bool RecordingOff => !Data.Settings.RecordingEnabled && IsToday;
    public bool HasUnattributed => Summary.UnattributedSeconds > 0;
    public bool HasDisabled => Summary.DisabledSeconds > 0;
    public string UnattributedLabel => "未归属时长　" + DisplayFormat.Duration(Summary.UnattributedSeconds);
    public string DisabledLabel => "未记录时长　" + DisplayFormat.Duration(Summary.DisabledSeconds);
    private bool showAllApps;
    public bool ShowAllApps { get => showAllApps; set { if (Set(ref showAllApps, value)) { Changed(nameof(SummaryApps)); Changed(nameof(HasHiddenApps)); Changed(nameof(HiddenAppsLabel)); } } }
    public int HiddenAppCount => Math.Max(0, Summary.Apps.Count - 3);
    public bool HasHiddenApps => HiddenAppCount > 0;
    public string HiddenAppsLabel => ShowAllApps ? "收起明细" : $"查看其余 {HiddenAppCount} 个 App";
    public IEnumerable<AppUsageRow> SummaryApps => Progressions.AppRows(Summary).Take(ShowAllApps ? int.MaxValue : 3);
    public IEnumerable<SessionRow> SessionRows => Progressions.SessionRows(Summary, Data);
    public IEnumerable<TodoDayRow> SummaryTodos => Progressions.TodoRows(Summary);

    // —— 待办 / 便签 / 设置页的占位与摘要 ——
    public bool HasTodos => Data.Todos.Any(x => x.IsScheduledOn(TodayKey));
    public bool AllTodosDone => HasTodos && Data.Todos.Where(x => x.IsScheduledOn(TodayKey)).All(x => x.IsCompleted);
    public double TodoCompletionPercent
    {
        get
        {
            var today = Data.Todos.Where(x => x.IsScheduledOn(TodayKey)).ToList();
            return today.Count == 0 ? 0 : Math.Round(100.0 * today.Count(x => x.IsCompleted) / today.Count);
        }
    }
    public string TodoProgressLabel
    {
        get
        {
            var today = Data.Todos.Where(x => x.IsScheduledOn(TodayKey)).ToList();
            return $"{today.Count(x => x.IsCompleted)} / {today.Count} 已完成";
        }
    }
    public string TodoDateLabel => TodayKey.Replace("-", ".");
    public string TodoShortLabel
    {
        get
        {
            var today = Data.Todos.Where(x => x.IsScheduledOn(TodayKey)).ToList();
            return $"{today.Count(x => x.IsCompleted)}/{today.Count}";
        }
    }
    public string TodoFooterLabel
    {
        get
        {
            var done = Data.Todos.Count(x => x.IsScheduledOn(TodayKey) && x.IsCompleted);
            return done == 0 ? "慢慢来，一件一件就很好。" : $"已经完成 {done} 件，进展看得见。";
        }
    }

    // —— 便签页：与 macOS 一致，历史按天分组，可切换 ——
    private bool showsHistory;
    public bool ShowsHistory { get => showsHistory; set { if (Set(ref showsHistory, value)) { Changed(nameof(NotesTitle)); Changed(nameof(NotesHistoryLabel)); Changed(nameof(NotesToggleIcon)); Changed(nameof(TodayNoteRows)); Changed(nameof(HistoryNoteGroups)); } } }
    public string NotesTitle => ShowsHistory ? "翻翻旧便签" : "今天的便签";
    public string NotesHistoryLabel => ShowsHistory ? "回到今天" : "历史便签";
    public Wpf.Ui.Controls.SymbolRegular NotesToggleIcon => ShowsHistory
        ? Wpf.Ui.Controls.SymbolRegular.ArrowLeft24 : Wpf.Ui.Controls.SymbolRegular.History24;
    public bool HasTodayNotes => Data.Notes.Any(x => x.DayKey == TodayKey);
    public bool HasHistoryNotes => Data.Notes.Any(x => x.DayKey != TodayKey);
    public int TodayNoteCount => Data.Notes.Count(x => x.DayKey == TodayKey);
    public int HistoryNoteCount => Data.Notes.Count(x => x.DayKey != TodayKey);
    public string NotesCountLabel => ShowsHistory ? $"{TodayNoteCount} 张" : $"{HistoryNoteCount} 张";
    public IEnumerable<NoteRow> TodayNoteRows => Data.Notes.Where(x => x.DayKey == TodayKey).OrderByDescending(x => x.UpdatedAt).Select(x => NoteProjections.Row(x, false));
    public IEnumerable<NoteDayGroup> HistoryNoteGroups => NoteProjections.History(Data.Notes, TodayKey);
    public string AppearanceLabel => Data.Settings.Appearance switch { "light" => "浅色", "dark" => "深色", _ => "跟随 Windows 系统" };
    public string TimerSummaryLabel => $"{Data.Settings.FocusMinutes} 分钟 · 长休息每 {Data.Settings.LongBreakEvery} 轮";
    public string ReviewLabel => Data.Settings.Review.ScheduleEnabled
        ? $"每天 {Data.Settings.Review.Hour:00}:{Data.Settings.Review.Minute:00} 自动生成"
        : Data.Settings.Review.AutoSummarizeSessions ? "每轮结束后自动整理" : "按需手动生成";
    public string RecordingLabel => Data.Settings.RecordingEnabled ? "已记录前台 App 时长" : "App 记录已关闭";
    public string DataStatusLabel => CanWrite ? $"可写入 · {StorageLabel}" : "只读 · 已停止写入";
    public string Goal { get => goal; set => Set(ref goal, value); }
    public string NewTodo { get => newTodo; set => Set(ref newTodo, value); }
    public string Feedback { get => feedback; set => Set(ref feedback, value); }
    public string AIStatus { get => aiStatus; set => Set(ref aiStatus, value); }
    public string SelectedDay { get => selectedDay; set { var parsed = DateTime.TryParse(value, out _); if (parsed && value != LocalTime.DayKey(DateTimeOffset.Now)) selectedDay = value; else selectedDay = TodayKey; Changed(); RefreshHistory(); } }
    public DailySummary Summary { get => summary; private set => Set(ref summary, value); }
    public bool IsHistoryDay => SelectedDay != TodayKey;
    public RelayCommand StartCommand { get; }
    public RelayCommand EndCommand { get; }
    public RelayCommand AddTodoCommand { get; }
    public RelayCommand BackupCommand { get; }
    public RelayCommand SaveSettingsCommand { get; }
    public RelayCommand FetchModelsCommand { get; }
    public RelayCommand TestAICommand { get; }

    public AppState(LocalRepository repository)
    {
        Repository = repository; Data = repository.Load(); engine = new(Data); engine.RecoverAfterLaunch();
        if (Data.Timer.Phase == TimerPhase.Paused && CanWrite) Save();
        summary = DailySummary.Build(SelectedDay, Data); ai = new(Provider);
        RefreshProgressCard();
        aiStatus = HasAPIKey ? $"{Provider.Name} 已配置，可生成成果总结" : $"尚未配置 {Provider.Name} 的 API Key";
        StartCommand = new(_ => StartOrPause(), _ => CanWrite); EndCommand = new(_ => EndEarly(), _ => CanWrite);
        AddTodoCommand = new(_ => AddTodo(NewTodo), _ => CanWrite); BackupCommand = new(_ => Backup());
        SaveSettingsCommand = new(_ => SaveSettings()); FetchModelsCommand = new(_ => _ = FetchModels()); TestAICommand = new(_ => _ = TestAI());
        timer.Tick += Tick; timer.Start(); clock.Start(); SystemEvents.SessionSwitch += SessionSwitch; SystemEvents.PowerModeChanged += PowerModeChanged;
        RefreshAll();
        if (CanWrite) foreach (var note in Data.Notes.Where(x => x.IsOpen).ToList()) OpenNote(note.ID, false);
    }
    public void ShowNote(Guid id) => OpenNote(id);
    public void CreateNote()
    {
        if (!CanWrite) return; var note = new StickyNote { LocalDay = TodayKey }; Data.Notes.Add(note); Commit(); OpenNote(note.ID);
    }
    public void OpenNote(Guid id, bool activate = true)
    {
        if (!notes.TryGetValue(id, out var window))
        {
            var note = Data.Notes.FirstOrDefault(x => x.ID == id); if (note is null) return;
            window = new NoteWindow(this, note); notes[id] = window; window.Closed += (_, _) => notes.Remove(id);
        }
        var current = Data.Notes.First(x => x.ID == id); current.IsOpen = true; Commit(); window.Show(); if (activate) { window.WindowState = WindowState.Normal; window.Activate(); }
    }
    public void ContinueNote(Guid id)
    {
        var source = Data.Notes.FirstOrDefault(x => x.ID == id); if (source is null || !CanWrite) return;
        if (source.DayKey == TodayKey) { OpenNote(id); return; }
        var note = Data.Notes.FirstOrDefault(x => x.ContinuedFromNoteID == id && x.DayKey == TodayKey);
        if (note is null) { note = new() { Text = source.Text, LocalDay = TodayKey, ContinuedFromNoteID = id, Width = source.Width, Height = source.Height }; Data.Notes.Add(note); }
        Commit(); OpenNote(note.ID);
    }
    public void DeleteNote(Guid id)
    {
        if (!CanWrite || MessageBox.Show("删除后无法在应用内撤销。确定删除这张便签吗？", "删除便签", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        Data.Notes.RemoveAll(x => x.ID == id); if (notes.Remove(id, out var window)) window.Close(); Commit(); Feedback = "便签已删除";
    }
    public void UpdateNote(Guid id, string text) { var note = Data.Notes.FirstOrDefault(x => x.ID == id); if (note is null || !CanWrite) return; note.Text = text; note.UpdatedAt = DateTimeOffset.UtcNow; Commit(false); }
    public void UpdateNoteFrame(Guid id, Window window) { var note = Data.Notes.FirstOrDefault(x => x.ID == id); if (note is null || !CanWrite) return; note.X = window.Left; note.Y = window.Top; note.Width = window.Width; note.Height = window.Height; Commit(false); }
    public void SetNoteOpen(Guid id, bool open) { var note = Data.Notes.FirstOrDefault(x => x.ID == id); if (note is not null && CanWrite) { note.IsOpen = open; Commit(false); } }
    public int ConvertNoteToTodos(string text)
    {
        var lines = text.Split('\n').Select(x => x.Trim()).Where(x => x.Length > 0).ToList(); if (!CanWrite) return 0;
        foreach (var line in lines) Data.Todos.Add(new() { Text = line, LocalDay = TodayKey, ScheduledDays = [TodayKey] }); Commit(); return lines.Count;
    }
    public void ExportNote(Guid id, string text)
    {
        var dialog = new SaveFileDialog { Filter = "文本文件 (*.txt)|*.txt", FileName = Data.Notes.FirstOrDefault(x => x.ID == id)?.Title + ".txt", AddExtension = true, DefaultExt = ".txt" };
        if (dialog.ShowDialog() == true) { try { File.WriteAllText(dialog.FileName, text); Feedback = "TXT 已导出"; } catch (Exception ex) { Feedback = "导出失败：" + ex.Message; } }
    }
    private void StartOrPause()
    {
        if (!CanWrite || locked) { if (locked) Feedback = "设备仍处于锁屏状态"; return; }
        if (Data.Timer.Phase == TimerPhase.Running) { AdvanceToNow(); engine.Pause("手动暂停", DateTimeOffset.UtcNow); lastTick = null; Commit(); }
        else { engine.Start(DateTimeOffset.UtcNow, Goal); Goal = ""; lastTick = clock.Elapsed; Commit(); }
    }
    private void EndEarly()
    {
        AdvanceToNow(); var ended = Data.Timer.Stage == TimerStage.Focus ? Data.Timer.SessionID : null; engine.EndEarlyOrSkip(DateTimeOffset.UtcNow); lastTick = null; Commit();
        if (ended is Guid id) { var interval = Data.Intervals.Where(x => x.SessionID == id).Sum(x => x.Seconds); if (Data.Settings.Review.AutoSummarizeSessions && interval >= 60) _ = GenerateReview(WorkScope.ForSession(id)); }
    }
    private void Tick(object? sender, EventArgs e)
    {
        if (Data.Timer.Phase == TimerPhase.Running && locked) { AdvanceToNow(); engine.Pause("锁屏已暂停", DateTimeOffset.UtcNow); lastTick = null; Commit(); return; }
        var dayBefore = TodayKey; AdvanceToNow(); if (DateTime.UtcNow - lastSaved > TimeSpan.FromSeconds(2) && CanWrite) { Save(); lastSaved = DateTime.UtcNow; }
        Changed(nameof(Remaining)); Changed(nameof(TodayKey)); Changed(nameof(StatusText)); Changed(nameof(PrimaryAction));
        Changed(nameof(PrimarySymbol)); Changed(nameof(IsRunning)); Changed(nameof(CanEndEarly)); Changed(nameof(CanSkipBreak));
        Changed(nameof(EndEarlyLabel)); Changed(nameof(HeaderDate)); Changed(nameof(TodayMinutes)); Changed(nameof(TodayCompleted));
        Changed(nameof(CanEditGoal)); Changed(nameof(CurrentSessionGoal)); Changed(nameof(HasCurrentSessionGoal));
        // 计时进行中每秒重算一次进展卡片，让「本日投入」跟着走。
        if (Data.Timer.Phase == TimerPhase.Running || Data.Timer.Phase == TimerPhase.Paused) RefreshProgressCard();
        if (dayBefore != TodayKey) RefreshAll();
        if (Data.Settings.Review.ScheduleEnabled && Data.LastReviewAttemptDay != TodayKey && DateTime.Now.TimeOfDay >= new TimeSpan(Data.Settings.Review.Hour, Data.Settings.Review.Minute, 0)) _ = GenerateReview(WorkScope.ForDay(TodayKey), scheduled: true);
    }
    private void AdvanceToNow()
    {
        var nowTick = clock.Elapsed; if (lastTick is not TimeSpan previous) { lastTick = nowTick; return; }
        var elapsed = (nowTick - previous).TotalSeconds; lastTick = nowTick;
        if (elapsed <= 0) return; var session = Data.Timer.SessionID; var completed = engine.Advance(elapsed, DateTimeOffset.UtcNow, new ForegroundAppService().Current(), Data.Settings.RecordingEnabled);
        if (completed) { Notify(TimerStage.Label(Data.Timer.Stage) + "完成", Data.Timer.NextStage == TimerStage.Focus ? "休息结束了，准备好再开始。" : "这一轮完成了，休息一下吧。"); Commit(); if (session is Guid id && Data.Settings.Review.AutoSummarizeSessions) _ = GenerateReview(WorkScope.ForSession(id)); }
    }
    public void PauseForSystem(string reason) { if (Data.Timer.Phase != TimerPhase.Running) return; AdvanceToNow(); engine.Pause(reason, DateTimeOffset.UtcNow); lastTick = null; Commit(); }
    private void SessionSwitch(object sender, SessionSwitchEventArgs e) { locked = e.Reason == SessionSwitchReason.SessionLock; Dispatcher.CurrentDispatcher.Invoke(() => { if (locked) PauseForSystem("锁屏已暂停"); }); }
    private void PowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) Dispatcher.CurrentDispatcher.Invoke(() => PauseForSystem("系统睡眠已暂停"));
        if (e.Mode == PowerModes.Resume) lastTick = clock.Elapsed;
    }
    public void Notify(string title, string body) => NotificationRequested?.Invoke(title, body, Data.Settings.SoundEnabled, Data.Settings.NotificationsEnabled);
    public void AddTodo(string text)
    {
        if (!CanWrite || string.IsNullOrWhiteSpace(text)) return; Data.Todos.Add(new() { Text = text.Trim(), LocalDay = TodayKey, ScheduledDays = [TodayKey] }); NewTodo = ""; Commit();
    }
    public void ToggleTodo(Guid id) { AdvanceToNow(); var item = Data.Todos.FirstOrDefault(x => x.ID == id && x.IsScheduledOn(TodayKey)); if (item is null || !CanWrite) return; item.CompletedAt = item.CompletedAt.HasValue ? null : DateTimeOffset.UtcNow; item.CompletedLocalDay = item.CompletedAt.HasValue ? TodayKey : null; Commit(); }
    public void UpdateTodo(Guid id, string text) { var item = Data.Todos.FirstOrDefault(x => x.ID == id && x.IsScheduledOn(TodayKey)); if (item is not null && CanWrite && !string.IsNullOrWhiteSpace(text)) { item.Text = text.Trim(); Commit(); } }
    public void DeleteTodo(Guid id) { if (!CanWrite || !deletedTodos.Remove(id, TodayKey, Data.Todos)) return; Commit(); Changed(nameof(LastDeleted)); }
    public void UndoTodo() { if (!CanWrite || deletedTodos.RestoreLast(Data.Todos) is null) return; Commit(); Changed(nameof(LastDeleted)); }
    public void MoveTodoToToday(Guid id) { var item = Data.Todos.FirstOrDefault(x => x.ID == id); if (item is not null && !item.IsScheduledOn(TodayKey) && CanWrite) { item.ScheduledDays.Add(TodayKey); Commit(); } }
    public void ScheduleSelectedCarryovers()
    {
        if (!CanWrite) return;
        var ids = carryoverRows.Where(x => x.IsSelected).Select(x => x.ID).ToList();
        var changed = TodoCarryover.Schedule(ids, TodayKey, Data.Todos);
        Feedback = changed.Count == 0 ? "请先选择要顺延的待办" : $"已把 {changed.Count} 件待办安排到今天";
        if (changed.Count > 0) Commit();
    }
    public void UndoCarryover(Guid id)
    {
        if (!CanWrite) return;
        var result = TodoCarryover.UndoSchedule(id, TodayKey, Data.Todos);
        Feedback = result switch
        {
            TodoCarryoverUndoResult.Undone => "已撤销今天安排，原待办保留在原日期",
            TodoCarryoverUndoResult.Missing => "没有找到这条待办",
            TodoCarryoverUndoResult.Completed => "已完成的待办不能撤销安排",
            _ => "这条待办今天没有单独安排",
        };
        if (result == TodoCarryoverUndoResult.Undone) Commit();
    }
    public void RefreshHistory() { Summary = DailySummary.Build(SelectedDay, Data); NotifySummary(); }
    private void NotifySummary()
    {
        RefreshHeatmap();
        foreach (var name in new[] { nameof(IsToday), nameof(SelectedDayLabel), nameof(CanMoveNext), nameof(SummaryMinutes),
            nameof(SummarySentence), nameof(HasEarlySessions), nameof(EarlySessionsLabel), nameof(SummaryCompletedTodos),
            nameof(SummaryCompletedSessions),
            nameof(SummaryTodoCount), nameof(HasSummaryTodos), nameof(HasSummarySessions), nameof(DayProgressTitle),
            nameof(HasApps), nameof(ShowEmptyApps), nameof(RecordingOff), nameof(HasUnattributed), nameof(HasDisabled),
            nameof(UnattributedLabel), nameof(DisabledLabel), nameof(HiddenAppCount), nameof(HasHiddenApps),
            nameof(HiddenAppsLabel), nameof(SummaryApps), nameof(SessionRows), nameof(SummaryTodos) }) Changed(name);
    }
    /// 选中日期变化时也要重算，紧凑视图才能描出当前查看的那一天。
    private void RefreshHeatmap()
    {
        heatmapRange = FocusHeatmapRange.Build(Data.Intervals, 13);
        HeatmapWeeks = HeatmapProjections.Weeks(heatmapRange, SelectedDay);
        Changed(nameof(HeatmapWeeks)); Changed(nameof(HeatmapSummaryLabel));
        Changed(nameof(HeatmapRangeLabel)); Changed(nameof(HasHeatmapRecords));
    }
    /// 进展卡片需要聚合区间与待办，算一次缓存下来，避免每秒重复扫描。
    private void RefreshProgressCard()
    {
        currentProgress = Progressions.ProgressCardFor(Data, Data.Timer.SessionID ?? Data.Sessions.LastOrDefault()?.ID);
        Changed(nameof(CurrentProgress)); Changed(nameof(HasCurrentProgress));
    }
    public void MoveDay(int days) { if (DateTime.TryParse(SelectedDay, out var date) && date.AddDays(days).Date <= DateTime.Today) SelectedDay = LocalTime.DayKey(new DateTimeOffset(date.AddDays(days))); }
    public void OpenWork(WorkScope scope)
    {
        if (!CanWrite) return; EnsureWorkRecord(scope);
        if (!workWindows.TryGetValue(scope.Key, out var window)) { window = new(this, scope); workWindows[scope.Key] = window; window.Closed += (_, _) => workWindows.Remove(scope.Key); }
        window.Show(); window.Activate();
    }
    public WorkRecord? WorkRecord(WorkScope scope) => ReviewContextBuilder.Record(scope, Data);
    public WorkRecord EnsureWorkRecord(WorkScope scope)
    {
        var record = WorkRecord(scope); if (record is not null) return record;
        record = new() { LocalDay = scope.Day ?? Data.Sessions.FirstOrDefault(x => x.ID == scope.SessionID)?.EndedLocalDay ?? TodayKey, SessionID = scope.SessionID }; Data.WorkRecords.Add(record); Commit(); return record;
    }
    public void UpdateWorkText(WorkScope scope, string text) { if (!CanWrite) return; var record = EnsureWorkRecord(scope); record.UserText = text; record.UpdatedAt = DateTimeOffset.UtcNow; Save(); }
    public async Task AddWorkImages(WorkScope scope)
    {
        if (!CanWrite || generating.Contains(scope.Key)) return; var dialog = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.gif|所有文件|*.*", Multiselect = true }; if (dialog.ShowDialog() != true) return;
        var record = EnsureWorkRecord(scope); if (record.Images.Count + dialog.FileNames.Length > 6) { Feedback = "每条成果记录最多添加 6 张图片"; return; }
        try { await Task.Run(() => WorkImageStore.Import(dialog.FileNames, record, Repository.AttachmentsPath)); record.UpdatedAt = DateTimeOffset.UtcNow; Commit(); }
        catch (Exception ex) { Feedback = "图片导入失败：" + ex.Message; }
    }
    public void RemoveWorkImage(WorkScope scope, Guid id) { if (!CanWrite || generating.Contains(scope.Key)) return; var record = EnsureWorkRecord(scope); record.Images.RemoveAll(x => x.ID == id); Commit(); }
    public string WorkImagePath(WorkImage image) => Path.Combine(Repository.AttachmentsPath, image.FileName);
    public async Task GenerateReview(WorkScope scope, bool scheduled = false)
    {
        if (!CanWrite || generating.Contains(scope.Key)) return; if (scheduled) { Data.LastReviewAttemptDay = TodayKey; Save(); }
        generating.Add(scope.Key); NotifyWork(scope);
        try
        {
            var provider = Provider; var client = ai; var key = CredentialStore.Read(provider.ID) ?? throw new InvalidOperationException("请先在设置中保存 API Key。"); EnsureWorkRecord(scope);
            var context = ReviewContextBuilder.Build(scope, Data); var images = context.Images.Select(x => (x, File.Exists(WorkImagePath(x)) ? File.ReadAllBytes(WorkImagePath(x)) : throw new InvalidDataException("有图片未能读取，请重新添加。"))).ToList();
            var content = await client.Summarize(context.Text, images, key, lifetime.Token);
            if (client != ai || provider != Provider || !CanWrite) return;
            var record = EnsureWorkRecord(scope); record.Summary = new() { Content = content, Model = provider.DefaultModel, ContextDigest = context.Digest, ImageIDs = context.Images.Select(x => x.ID).ToList() }; record.UpdatedAt = DateTimeOffset.UtcNow; Commit();
            if (scheduled) Data.LastReviewError = null; Feedback = "AI 总结已保存"; if (scheduled) Notify("每日回顾已生成", "打开番茄小记，查看今天留下的进展。");
        }
        catch (Exception ex) when (ex is not OperationCanceledException) { if (scheduled) Data.LastReviewError = ex.Message; Feedback = "AI 回顾失败：" + ex.Message; }
        finally { generating.Remove(scope.Key); if (scheduled && CanWrite) Save(); NotifyWork(scope); }
    }
    public bool IsGenerating(WorkScope scope) => generating.Contains(scope.Key);
    private void NotifyWork(WorkScope scope) { if (workWindows.TryGetValue(scope.Key, out var window)) window.Refresh(); }
    public void Backup()
    {
        if (!CanWrite) return; AdvanceToNow(); Save(); try { var path = Repository.Backup(); Feedback = path is null ? "暂无可备份的数据" : "本地数据与图片已备份"; }
        catch (Exception ex) { Feedback = "备份失败：" + ex.Message; }
        if (MessageBox.Show($"备份目录：\n{Path.Combine(Repository.Root, "Backups")}\n\n是否打开备份目录？", "备份完成", MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes) Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Path.Combine(Repository.Root, "Backups")}\"") { UseShellExecute = true });
    }
    public void ChangeProvider(string id) { Data.Settings.AI.ProviderID = id; Data.Settings.AI.ModelOverride = ""; ai.Dispose(); ai = new(Provider); Models.Clear(); SaveSettings(); AIStatus = HasAPIKey ? $"{Provider.Name} 已配置" : $"尚未配置 {Provider.Name} 的 API Key"; Changed(nameof(Provider)); Changed(nameof(HasAPIKey)); }
    public void SetModel(string model) { Data.Settings.AI.ModelOverride = model; Save(); Changed(nameof(Provider)); }
    public void SaveAPIKey(string key) { if (string.IsNullOrWhiteSpace(key)) return; try { CredentialStore.Save(Provider.ID, key); AIStatus = "API Key 已使用 Windows 当前用户加密保存"; Changed(nameof(HasAPIKey)); } catch (Exception ex) { AIStatus = ex.Message; } }
    public void RemoveAPIKey() { CredentialStore.Remove(Provider.ID); AIStatus = "本机密钥已移除"; Changed(nameof(HasAPIKey)); }
    public async Task FetchModels()
    {
        if (BusyAI) return; BusyAI = true; Changed(nameof(BusyAI));
        try { var key = CredentialStore.Read(Provider.ID) ?? throw new InvalidOperationException("请先保存 API Key。"); var models = await ai.FetchModels(key, lifetime.Token); Models.Clear(); foreach (var model in models) Models.Add(model); AIStatus = $"已获取 {models.Count} 个可用模型，请选择"; }
        catch (Exception ex) { AIStatus = ex.Message; }
        finally { BusyAI = false; Changed(nameof(BusyAI)); }
    }
    public async Task TestAI() { await FetchModels(); if (!AIStatus.StartsWith("已获取")) return; AIStatus = $"{Provider.Name} 连接成功，模型列表已读取"; }
    private void SaveSettings()
    {
        if (Data.Settings.FocusMinutes is < 1 or > 180 || Data.Settings.ShortBreakMinutes is < 1 or > 120 || Data.Settings.LongBreakMinutes is < 1 or > 180 || Data.Settings.LongBreakEvery is < 1 or > 20) { Feedback = "请填写有效的分钟数与轮数。"; return; }
        if (Data.Settings.Review.Hour is < 0 or > 23 || Data.Settings.Review.Minute is < 0 or > 59) { Feedback = "回顾时间无效。"; return; }
        if (Data.Timer.Phase == TimerPhase.Idle) Data.Timer.TargetSeconds = Data.Timer.RemainingSeconds = Data.Settings.Duration(TimerStage.Focus); Commit(); Feedback = "设置已保存"; Application.Current.Windows.OfType<SettingsWindow>().FirstOrDefault()?.Refresh();
    }
    public void Save()
    {
        if (!CanWrite) return;
        try { Repository.Save(Data); }
        catch (Exception ex) { Repository.CanWrite = false; Repository.LoadError = ex.Message; Feedback = "保存失败，已停止写入：" + ex.Message; }
    }
    public void Commit(bool refresh = true) { AdvanceToNow(); Save(); if (refresh) RefreshAll(); }
    public void RefreshAll()
    {
        foreach (var name in new[] { nameof(Data), nameof(Remaining), nameof(StatusText), nameof(PrimaryAction), nameof(TimerCaption), nameof(CanEndEarly), nameof(CanSkipBreak), nameof(EndEarlyLabel), nameof(TodayTodos), nameof(TodayMinutes), nameof(TodayCompleted), nameof(VisibleNotes), nameof(HistoryNotes), nameof(Provider), nameof(HasAPIKey),
            nameof(IsFocusStage), nameof(IsRunning), nameof(CompletedInSet), nameof(LongBreakEvery), nameof(SetLabel), nameof(RoundDots), nameof(HasRoundDots), nameof(PrimarySymbol),
            nameof(CanEditGoal), nameof(CurrentSessionGoal), nameof(HasCurrentSessionGoal),
            nameof(HeaderDate), nameof(HasTodos), nameof(TodoProgressLabel), nameof(HasTodayNotes), nameof(HasHistoryNotes),
            nameof(AppearanceLabel), nameof(TimerSummaryLabel), nameof(ReviewLabel), nameof(RecordingLabel), nameof(DataStatusLabel), nameof(StorageLabel),
            nameof(HasTodos), nameof(AllTodosDone), nameof(TodoCompletionPercent), nameof(TodoProgressLabel), nameof(TodoDateLabel),
            nameof(TodoShortLabel), nameof(TodoFooterLabel), nameof(AIStatusLabel),
            nameof(HasTodayNotes), nameof(HasHistoryNotes), nameof(TodayNoteCount), nameof(HistoryNoteCount), nameof(NotesCountLabel),
            nameof(TodayNoteRows), nameof(HistoryNoteGroups) }) Changed(name);
        RefreshCarryoverRows();
        RefreshProgressCard(); RefreshHistory();
    }
    private void RefreshCarryoverRows()
    {
        var selected = carryoverRows.Where(x => x.IsSelected).Select(x => x.ID).ToHashSet();
        var rows = TodoCarryover.Candidates(Data.Todos, TodayKey).Select(x => new CarryoverRow
        {
            ID = x.ID, Text = x.Text,
            Detail = $"来自 {x.LocalDay} · 最近安排 {x.EffectiveScheduledDay}",
            IsSelected = selected.Contains(x.ID),
        }).ToList();
        carryoverRows.Clear(); carryoverRows.AddRange(rows);
        Changed(nameof(CarryoverRows)); Changed(nameof(HasCarryoverRows)); Changed(nameof(CarryoverCountLabel));
    }
    public void ShowDataFolder() => Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{Repository.FilePath}\"") { UseShellExecute = true });
    public void PrepareForQuit()
    {
        IsQuitting = true;
        foreach (var note in notes.Values.ToList()) note.Flush(); if (!CanWrite) return; AdvanceToNow(); if (Data.Timer.Phase == TimerPhase.Running) engine.Pause("应用退出已暂停", DateTimeOffset.UtcNow); Save();
    }
    public void Dispose() { lifetime.Cancel(); lifetime.Dispose(); timer.Stop(); SystemEvents.SessionSwitch -= SessionSwitch; SystemEvents.PowerModeChanged -= PowerModeChanged; ai.Dispose(); if (CanWrite) Save(); }
}
