using System.Diagnostics;
using TomatoNotes.Core;

namespace TomatoNotes.Windows;

/// 专注守护的运行时循环，对应 macOS 的 FocusGuardController。
/// 前台读取、UIA 取网址与 AI 判定都放在专用后台线程，避免每秒阻塞界面；
/// 只有通知与状态回写交给 UI 线程处理。
public sealed class FocusGuardController : IDisposable
{
    /// 由 UI 线程发布的不可变快照，后台线程只读这一份，不直接碰资料。
    public sealed record Snapshot(bool Active, Guid SessionID, FocusGuardSettings Settings, FocusGuardPlan Plan, bool HasAPIKey);

    private static readonly TimeSpan Period = TimeSpan.FromMilliseconds(1500);

    private readonly Func<GuardTarget, string, CancellationToken, Task<FocusAssessment>> assess;
    private readonly Action<string, string> notify;
    private readonly Action<GuardTarget> allow;
    private readonly Action publish;

    private readonly GuardForegroundService foreground = new();
    private readonly BrowserPageReader pages = new();
    private readonly GuardCloser closer = new();
    private readonly CancellationTokenSource lifetime = new();
    private readonly Thread loop;
    private readonly object gate = new();

    private Snapshot? snapshot;
    private GuardDwellMonitor monitor;
    private readonly HashSet<string> reviewed = [];
    private Guid round;
    private Guid generation = Guid.NewGuid();
    private GuardTarget? current;
    private string status = "本轮尚未开始守护";
    private int checks;
    private int inputTokens;
    private int outputTokens;
    private bool assessing;
    private bool running;

    public FocusGuardController(
        Func<GuardTarget, string, CancellationToken, Task<FocusAssessment>> assess,
        Action<string, string> notify,
        Action<GuardTarget> allow,
        Action publish)
    {
        this.assess = assess; this.notify = notify; this.allow = allow; this.publish = publish;
        loop = new Thread(Run) { IsBackground = true, Name = "FocusGuard" };
        loop.SetApartmentState(ApartmentState.STA);
        loop.Start();
    }

    public string Status { get { lock (gate) return status; } }
    public int Checks { get { lock (gate) return checks; } }
    public int InputTokens { get { lock (gate) return inputTokens; } }
    public int OutputTokens { get { lock (gate) return outputTokens; } }
    public bool Assessing { get { lock (gate) return assessing; } }
    public GuardTarget? Current { get { lock (gate) return current; } }

    /// UI 线程每秒发布一次快照；轮次或计划变化时清空本轮累计状态。
    public void Update(Snapshot? next)
    {
        lock (gate)
        {
            snapshot = next;
            if (next is null) { round = Guid.Empty; return; }
            if (next.SessionID == round) return;
            round = next.SessionID;
            generation = Guid.NewGuid();
            monitor.Reset(); reviewed.Clear(); pages.Invalidate();
            checks = 0; inputTokens = 0; outputTokens = 0; assessing = false;
            status = next.Plan.AllowAIClosing ? "守护生效：离开白名单会提醒，超时后由 AI 核对" : "守护生效：离开白名单只提醒，不会自动关闭";
        }
    }

    /// 用户改名、放行或修改计划后作废在途判定，并让停留重新计时。
    public void Invalidate(string? reason = null)
    {
        lock (gate)
        {
            generation = Guid.NewGuid();
            monitor.Reset(); pages.Invalidate();
            if (reason is not null) status = reason;
        }
    }

    private void Run()
    {
        while (!lifetime.IsCancellationRequested)
        {
            try { Step(); }
            catch (Exception ex) when (ex is not OperationCanceledException) { SetStatus("守护检查失败：" + ex.Message); }
            try { Thread.Sleep(Period); } catch { return; }
        }
    }

    private void Step()
    {
        Snapshot? snap;
        lock (gate) { snap = snapshot; if (assessing) return; }
        if (snap is null || !snap.Active)
        {
            lock (gate) { monitor.Reset(); current = null; }
            return;
        }
        var front = foreground.Current();
        if (front is null)
        {
            lock (gate) { monitor.Reset(); current = null; }
            return;
        }
        var target = Sample(front);
        var settings = snap.Settings;
        int used;
        lock (gate) { current = target; used = checks; }
        var identity = target.Identity(snap.Plan.Allows(target.AppID, target.Url));
        if (identity is null)
        {
            lock (gate) { monitor.Reset(); status = "正在使用本轮白名单内的内容"; }
            Publish();
            return;
        }
        // 本轮已核对过的内容不再计时，也不重复请求 AI，与 macOS 一致。
        bool done; lock (gate) done = reviewed.Contains(identity);
        if (done)
        {
            lock (gate) { monitor.Reset(); status = "这一项本轮已核对过，不再重复请求 AI"; }
            Publish();
            return;
        }
        var mayAssess = GuardAssessmentPolicy.MayAssess(settings, snap.Plan, snap.HasAPIKey, target, used);
        if (!snap.HasAPIKey) SetStatus("未配置密钥：只提醒，不做 AI 判定");
        else if (!snap.Plan.AllowAIClosing && !settings.AIRelevance) SetStatus("当前不在白名单内，停留超时后提醒");
        else if (used >= GuardAssessmentPolicy.CheckLimit(settings)) SetStatus("本轮已达到 AI 判断上限，之后仅提醒");
        else if (!target.MayAssess) SetStatus(target.IsBrowser ? "读不到当前网址或处于隐私模式：只提醒，不判定" : "读不到窗口标题：只提醒，不判定");
        else SetStatus(snap.Plan.AllowAIClosing ? "当前不在白名单内，停留超时后提醒并交给 AI 核对" : "当前不在白名单内，停留超时后由 AI 判断是否相关");

        var action = monitor.Update(identity, Environment.TickCount64 / 1000.0, settings, mayAssess);
        if (action == GuardAction.Remind)
        {
            SetStatus(mayAssess
                ? $"已提醒，{Math.Max(5, settings.GraceSeconds)} 秒后仍未离开将交由 AI 判断" + (snap.Plan.AllowAIClosing ? "" : "（不关闭）")
                : "已提醒，本轮对当前内容仅提醒");
            notify("回到这一轮的学习吧", $"目标：{snap.Plan.Goal}\n当前停留：{Subject(target)}");
            Publish();
        }
        else if (action == GuardAction.Assess)
        {
            _ = AssessAsync(target, front, snap);
        }
        else Publish();
    }

    private GuardTarget Sample(GuardForeground front)
    {
        if (!BrowserCatalog.IsBrowser(front.AppID)) { pages.Invalidate(); return new(front.AppID, front.AppName, front.WindowTitle, null, null); }
        var url = pages.Read(front.Handle, front.WindowTitle);
        return new(front.AppID, front.AppName, front.WindowTitle, url, BrowserWindowTitle.PageTitle(front.WindowTitle));
    }



    private async Task AssessAsync(GuardTarget target, GuardForeground front, Snapshot snap)
    {
        var token = generation;
        lock (gate)
        {
            assessing = true;
            var subject = target.IsBrowser ? "当前网页" : "当前应用";
            status = snap.Plan.AllowAIClosing ? $"关闭前由 AI 核对{subject}…" : $"由 AI 判断{subject}是否与本轮学习相关…";
        }
        Publish();
        try
        {
            var result = await assess(target, snap.Plan.Goal, lifetime.Token).ConfigureAwait(false);
            lock (gate)
            {
                if (token != generation) return;
                checks = Math.Min(99, checks + 1);
                inputTokens += Math.Max(0, result.InputTokens);
                outputTokens += Math.Max(0, result.OutputTokens);
            }
            // 关闭前重新确认：窗口、进程与网页都还是刚才那一个，且仍不在白名单内。
            var still = foreground.Current();
            if (still is null || still.Handle != front.Handle || still.ProcessID != front.ProcessID)
            {
                SetStatus("已切换窗口，取消本次关闭");
                return;
            }
            var fresh = Sample(still);
            var identity = fresh.Identity(snap.Plan.Allows(fresh.AppID, fresh.Url));
            if (identity is null) { SetStatus("已回到白名单，取消本次关闭"); return; }
            lock (gate)
            {
                if (token != generation) return;
                reviewed.Add(identity);
                current = fresh;
            }
            var relevance = result.Relevance;
            if (relevance.Verdict == FocusVerdict.Related)
            {
                // AI 认定与本轮目标相关时顺手放行，本轮不必反复判断同一页；关闭授权与此无关。
                if (snap.Settings.AIRelevance) allow(fresh);
                SetStatus($"AI 判定与本轮学习相关：{relevance.Reason}");
                notify("这个内容可以继续学习", relevance.Reason);
                return;
            }
            if (!GuardAssessmentPolicy.MayClose(snap.Plan, relevance))
            {
                SetStatus($"本轮保留：{relevance.Reason}");
                notify(relevance.Verdict == FocusVerdict.Unrelated ? "AI 判定与本轮学习无关，已保留" : "AI 无法确认，已保留", relevance.Reason);
                return;
            }
            Close(fresh, still, snap.Plan, relevance.Reason);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // 失败也计入本轮已核对，避免对着同一个内容反复重试，与 macOS 一致。
            lock (gate)
            {
                if (token == generation)
                {
                    var failed = target.Identity(snap.Plan.Allows(target.AppID, target.Url));
                    if (failed is not null) reviewed.Add(failed);
                }
            }
            SetStatus("AI 判定失败，已保留当前内容：" + ex.Message);
        }
        finally
        {
            lock (gate) if (token == generation) assessing = false;
            Publish();
        }
    }

    private void Close(GuardTarget target, GuardForeground front, FocusGuardPlan plan, string reason)
    {
        if (!GuardProcessPolicy.MayClose(front.AppID, foreground.ImagePath(front.ProcessID)))
        {
            SetStatus("系统或受保护进程，不会自动关闭");
            return;
        }
        var label = Subject(target);
        if (target.IsBrowser)
        {
            // SendInput 把按键送给当下的前台窗口，不是送给指定句柄：临发送前再确认一次目标仍在前台，
            // 否则上面重新读网址那几十毫秒里用户切走，Ctrl+W 会打进他刚切过去的程序。
            if (!foreground.IsForeground(front.Handle)) { SetStatus("已切换窗口，取消本次关闭"); return; }
            if (!closer.CloseBrowserTab(front.Handle)) { SetStatus("发送关闭标签失败，已保留页面"); return; }
            Thread.Sleep(900);
            if (!foreground.IsForeground(front.Handle)) { SetStatus($"已发送关闭：{label}"); notify("已收起无关页面", reason); return; }
            // 绕开地址栏缓存重新读一次，否则拿到的还是关闭前的网址。
            pages.Invalidate();
            var after = Sample(foreground.Current() ?? front);
            if (after.PageKey != target.PageKey || !closer.IsRunning(front.ProcessID))
            {
                SetStatus($"已关闭无关页面：{reason}");
                notify("已收起无关页面", reason);
                return;
            }
            if (!plan.AllowForceKill) { SetStatus("标签没有关闭，已保留（可在本轮授权强制关闭）"); return; }
        }
        else
        {
            closer.CloseWindow(front.Handle);
            Thread.Sleep(1500);
            if (!closer.IsRunning(front.ProcessID))
            {
                SetStatus($"已关闭无关应用：{reason}");
                notify("已关闭无关应用", reason);
                return;
            }
            if (!plan.AllowForceKill) { SetStatus("应用没有退出，可能有未保存内容，已保留"); return; }
        }
        // 强制结束是单独授权的动作：正常关闭无效时才用。
        if (!closer.ForceClose(front.ProcessID)) { SetStatus("强制结束失败，请手动关闭"); return; }
        SetStatus($"已强制结束：{label}");
        notify("已强制结束无关程序", reason);
    }

    private static string Subject(GuardTarget target)
        => target.IsBrowser
            ? (string.IsNullOrWhiteSpace(target.PageTitle) ? target.PageKey ?? target.AppName : target.PageTitle!)
            : target.AppName;

    private void SetStatus(string value) { lock (gate) status = value; Publish(); }
    private void Publish() { if (!running) return; try { publish(); } catch { } }

    public void Dispose()
    {
        running = false;
        lifetime.Cancel();
        try { loop.Join(2000); } catch { }
        lifetime.Dispose();
    }

    /// 由 AppState 在初始化完成后打开状态回写，避免构造期间回调尚未就绪。
    public void Start() => running = true;
}
