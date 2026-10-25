namespace TomatoNotes.Core;

/// <summary>UI-independent timer. elapsed is monotonic elapsed time, not a wall-clock interval.</summary>
public sealed class TimerEngine
{
    public AppData Data { get; private set; }
    public TimerSnapshot Timer => Data.Timer;
    public TimerEngine(AppData data) { Data = data; }
    public void RecoverAfterLaunch() { if (Timer.Phase == TimerPhase.Running) { Timer.Phase = TimerPhase.Paused; Timer.PauseReason = "已恢复上次计时，等待继续"; Timer.UpdatedAt = DateTimeOffset.UtcNow; } }
    public void Start(DateTimeOffset now, string? goal = null)
    {
        switch (Timer.Phase)
        {
            case TimerPhase.Running: return;
            case TimerPhase.Paused: Timer.Phase = TimerPhase.Running; Timer.PauseReason = null; break;
            default:
                if (Timer.Phase == TimerPhase.Completed) { Timer.Stage = Timer.NextStage ?? TimerStage.Focus; Timer.NextStage = null; }
                Timer.TargetSeconds = Timer.RemainingSeconds = Data.Settings.Duration(Timer.Stage); Timer.Phase = TimerPhase.Running; Timer.PauseReason = null;
                if (Timer.Stage == TimerStage.Focus)
                {
                    var session = new FocusSession { StartedAt = now, Goal = string.IsNullOrWhiteSpace(goal) ? null : goal.Trim()[..Math.Min(300, goal.Trim().Length)] };
                    Timer.SessionID = session.ID; Data.Sessions.Add(session);
                } else Timer.SessionID = null;
                break;
        }
        Timer.UpdatedAt = now;
    }
    public void Pause(string reason, DateTimeOffset now) { if (Timer.Phase == TimerPhase.Running) { Timer.Phase = TimerPhase.Paused; Timer.PauseReason = reason; Timer.UpdatedAt = now; } }
    public bool Advance(double elapsed, DateTimeOffset now, AppIdentity? app, bool recordingEnabled)
    {
        if (Timer.Phase != TimerPhase.Running || elapsed <= 0 || !double.IsFinite(elapsed)) return false;
        var used = Math.Min(elapsed, Timer.RemainingSeconds); var end = now.AddSeconds(-(elapsed - used)); var start = end.AddSeconds(-used);
        if (Timer.Stage == TimerStage.Focus && Timer.SessionID is Guid id)
        {
            foreach (var part in LocalTime.Split(start, end, used))
            {
                AppendInterval(part, id);
                var kind = !recordingEnabled ? UsageKind.Disabled : app is null ? UsageKind.Unattributed : UsageKind.App;
                AppendUsage(part, id, kind, app);
            }
        }
        Timer.RemainingSeconds = Math.Max(0, Timer.RemainingSeconds - used); Timer.UpdatedAt = end;
        if (Timer.RemainingSeconds <= .000001) { Complete(end); return true; }
        return false;
    }
    public void EndEarlyOrSkip(DateTimeOffset now)
    {
        if (Timer.Phase == TimerPhase.Completed || Timer.Stage != TimerStage.Focus) { if (Timer.NextStage == TimerStage.LongBreak || Timer.Stage == TimerStage.LongBreak) Timer.CompletedInSet = 0; ResetForFocus(now); return; }
        if (Timer.Phase is not (TimerPhase.Running or TimerPhase.Paused)) return;
        FinishSession(now, false, "提前结束"); ResetForFocus(now);
    }
    private void Complete(DateTimeOffset now)
    {
        var finished = Timer.Stage; Timer.Phase = TimerPhase.Completed; Timer.PauseReason = null;
        if (finished == TimerStage.Focus) { FinishSession(now, true, "自然完成"); Timer.CompletedInSet++; Timer.NextStage = Timer.CompletedInSet >= Data.Settings.LongBreakEvery ? TimerStage.LongBreak : TimerStage.ShortBreak; }
        else { if (finished == TimerStage.LongBreak) Timer.CompletedInSet = 0; Timer.NextStage = TimerStage.Focus; }
        Timer.SessionID = null;
    }
    private void FinishSession(DateTimeOffset now, bool completed, string reason)
    {
        var session = Data.Sessions.FirstOrDefault(x => x.ID == Timer.SessionID && x.EndedAt is null); if (session is null) return;
        session.EndedAt = now; session.EndedLocalDay = LocalTime.DayKey(now); session.EndTimeZoneID = LocalTime.TimeZoneID; session.Completed = completed; session.EndReason = reason; session.WhitelistedBundleIDs = null;
    }
    private void ResetForFocus(DateTimeOffset now) { Timer.Stage = TimerStage.Focus; Timer.Phase = TimerPhase.Idle; Timer.NextStage = null; Timer.SessionID = null; Timer.TargetSeconds = Timer.RemainingSeconds = Data.Settings.Duration(TimerStage.Focus); Timer.PauseReason = null; Timer.UpdatedAt = now; }
    private void AppendInterval((DateTimeOffset Start, DateTimeOffset End, string Day, double Seconds) part, Guid id)
    {
        var last = Data.Intervals.LastOrDefault();
        if (last is not null && last.SessionID == id && last.LocalDay == part.Day && Math.Abs((last.EndedAt - part.Start).TotalSeconds) < .005) { last.EndedAt = part.End; last.Seconds += part.Seconds; }
        else Data.Intervals.Add(new() { SessionID = id, StartedAt = part.Start, EndedAt = part.End, LocalDay = part.Day, TimeZoneID = LocalTime.TimeZoneID, Seconds = part.Seconds });
    }
    private void AppendUsage((DateTimeOffset Start, DateTimeOffset End, string Day, double Seconds) part, Guid id, string kind, AppIdentity? app)
    {
        var bundle = kind == UsageKind.App ? app?.BundleID : null; var last = Data.Usage.LastOrDefault();
        if (last is not null && last.SessionID == id && last.LocalDay == part.Day && last.Kind == kind && last.BundleID == bundle && Math.Abs((last.EndedAt - part.Start).TotalSeconds) < .005) { last.EndedAt = part.End; last.Seconds += part.Seconds; }
        else Data.Usage.Add(new() { SessionID = id, Kind = kind, AppName = kind == UsageKind.App ? app?.Name : null, BundleID = bundle, StartedAt = part.Start, EndedAt = part.End, LocalDay = part.Day, TimeZoneID = LocalTime.TimeZoneID, Seconds = part.Seconds });
    }
}
