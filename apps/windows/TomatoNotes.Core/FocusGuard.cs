using System.Globalization;
using System.Text.Json.Serialization;

namespace TomatoNotes.Core;

/// 与 macOS 的 TomatoCore/FocusGuard.swift 对应。
/// 判定对象是前台进程；浏览器再进一步精确到当前网页。
/// 字段名与 macOS 逐项一致，未知字段由扩展数据原样保留，不新增共享契约字段。
public sealed class FocusGuardSettings : JsonModel
{
    [JsonPropertyName("enabled")] public bool Enabled { get; set; }
    [JsonPropertyName("remindAfterSeconds")] public int RemindAfterSeconds { get => remindAfterSeconds; set => remindAfterSeconds = ClampRemind(value); }
    [JsonPropertyName("graceSeconds")] public int GraceSeconds { get => graceSeconds; set => graceSeconds = ClampGrace(value); }
    [JsonPropertyName("maxChecks")] public int MaxChecks { get => maxChecks; set => maxChecks = ClampChecks(value); }
    /// 让 AI 自行判断当前内容是否与本轮学习相关：只判断并放行，不代表授权关闭。
    /// 关闭仍要本轮单独打开 AllowAIClosing；macOS 暂不读取此字段，按未知字段原样保留。
    [JsonPropertyName("aiRelevance")] public bool AIRelevance { get; set; }
    [JsonPropertyName("reuseLastPlan")] public bool ReuseLastPlan { get; set; }
    [JsonPropertyName("lastGoal")] public string LastGoal { get => lastGoal; set => lastGoal = value ?? ""; }
    /// Windows 存进程标识（如 code.exe），macOS 存 bundleID；同为字符串，互不匹配但不影响各自使用。
    [JsonPropertyName("lastAppIDs")] public List<string> LastAppIDs { get => lastAppIDs; set => lastAppIDs = value ?? []; }
    [JsonPropertyName("lastPages")] public List<FocusPageRule> LastPages { get => lastPages; set => lastPages = value ?? []; }
    /// AI 关闭授权只在当前轮次的内存里有效：macOS 编码时恒写 false，Windows 连资料里的 true 也一并作废。
    [JsonPropertyName("lastAllowAIClosing")] public bool LastAllowAIClosing { get => false; set { } }
    [JsonPropertyName("favoritePages")] public List<FocusPageRule> FavoritePages { get => favoritePages; set => favoritePages = value ?? []; }

    // System.Text.Json 不会调用 [OnDeserialized]，所以范围夹取与空值兜底都放在赋值器里，
    // 读取资料和界面写入经过同一条路径；范围与 macOS FocusGuard.swift 的 init(from:) 逐项一致。
    private int remindAfterSeconds = 60, graceSeconds = 60, maxChecks = 3;
    private string lastGoal = "";
    private List<string> lastAppIDs = [];
    private List<FocusPageRule> lastPages = [], favoritePages = [];

    private static int ClampRemind(int value) => Math.Clamp(value, 5, 1800);
    private static int ClampGrace(int value) => Math.Clamp(value, 5, 600);
    private static int ClampChecks(int value) => Math.Clamp(value, 1, 5);

    /// 与 macOS 解码时的夹取范围一致，避免资料里写出越界数值。
    public void Normalize()
    {
        remindAfterSeconds = ClampRemind(remindAfterSeconds);
        graceSeconds = ClampGrace(graceSeconds);
        maxChecks = ClampChecks(maxChecks);
    }

    public bool HasLastPlan => !string.IsNullOrWhiteSpace(LastGoal);

    /// 沿用上一轮时不带关闭授权，与 macOS 的 reusablePlan 一致。
    public FocusGuardPlan? ReusablePlan => ReuseLastPlan && HasLastPlan
        ? new FocusGuardPlan(LastGoal, LastAppIDs, LastPages, false)
        : null;

    public void RememberDraft(FocusGuardPlan? plan)
    {
        var saved = ReuseLastPlan ? plan : null;
        LastGoal = saved?.Goal ?? "";
        LastAppIDs = saved is null ? [] : [.. saved.AppIDs];
        LastPages = saved?.Pages ?? [];
    }
}

/// 网页规则的 JSON 取值，与 macOS 的 FocusPageRule.Kind 原始值一致。
public static class FocusPageKind
{
    public const string Page = "page";
    public const string Site = "site";
}

/// 一条网页白名单规则：整页（含查询条件）或整站。
public sealed class FocusPageRule
{
    // 同 FocusGuardSettings：缺字段或写成 null 时在赋值器里兜住，不依赖 [OnDeserialized]。
    [JsonPropertyName("kind")] public string Kind { get => kind; set => kind = string.IsNullOrWhiteSpace(value) ? FocusPageKind.Page : value.Trim(); }
    [JsonPropertyName("value")] public string Value { get => ruleValue; set => ruleValue = value?.Trim() ?? ""; }
    [JsonPropertyName("title")] public string Title { get => title; set => title = value?.Trim() ?? ""; }
    [JsonIgnore] public string Id => Kind + ":" + Value;

    private string kind = FocusPageKind.Page, ruleValue = "", title = "";

    public FocusPageRule() { }
    public FocusPageRule(string kind, string value, string title) { Kind = kind; Value = value; Title = title; }

    /// 归一化整页地址：小写协议与主机，去掉账号密码与锚点，路径缺省补 "/"，
    /// 保留查询条件，避免把不同的视频或文档当成同一个学习页面。与 macOS 的 pageKey 同规则。
    public static string? PageKey(string address)
    {
        var text = (address ?? "").Trim();
        if (text.Length == 0 || !Uri.TryCreate(text, UriKind.Absolute, out var url)) return null;
        var scheme = url.Scheme.ToLowerInvariant();
        if (scheme is not ("http" or "https")) return null;
        var host = url.Host.ToLowerInvariant();
        if (host.Length == 0) return null;
        var path = url.AbsolutePath.Length == 0 ? "/" : url.AbsolutePath;
        var port = url.IsDefaultPort ? "" : ":" + url.Port.ToString(CultureInfo.InvariantCulture);
        return scheme + "://" + host + port + path + url.Query;
    }

    /// 归一化整站主机名：小写、去 www.、必须含点或为 localhost。与 macOS 的 siteHost 同规则。
    public static string? SiteHost(string value)
    {
        var text = (value ?? "").Trim();
        if (text.Length == 0) return null;
        var probe = text.Contains("://") ? text : "https://" + text;
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var url)) return null;
        var host = url.Host.ToLowerInvariant();
        if (host.Length == 0 || (!host.Contains('.') && host != "localhost")) return null;
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }

    public bool Matches(string address)
    {
        if (Kind == FocusPageKind.Site)
        {
            if (!Uri.TryCreate((address ?? "").Trim(), UriKind.Absolute, out var url)) return false;
            var host = url.Host.ToLowerInvariant();
            return host == Value || host.EndsWith("." + Value, StringComparison.Ordinal);
        }
        return PageKey(address) == Value;
    }
}

/// 一轮生效的守护计划。授权只在本轮内存中存在，不写进资料。
public sealed class FocusGuardPlan
{
    public string Goal { get; }
    public HashSet<string> AppIDs { get; }
    public List<FocusPageRule> Pages { get; }
    public bool AllowAIClosing { get; }
    /// 强制结束进程需要单独授权；默认只用正常关闭，给应用留下保存机会。
    public bool AllowForceKill { get; }

    public FocusGuardPlan(string goal, IEnumerable<string> appIDs, IEnumerable<FocusPageRule> pages, bool allowAIClosing, bool allowForceKill = false)
    {
        Goal = goal ?? "";
        // 浏览器不放行整个进程：要具体到网页，与 macOS 剔除 Chrome 的做法一致。
        AppIDs = appIDs.Where(x => !string.IsNullOrWhiteSpace(x) && !BrowserCatalog.IsBrowser(x)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Pages = pages?.ToList() ?? [];
        AllowAIClosing = allowAIClosing;
        AllowForceKill = allowForceKill && allowAIClosing;
    }

    /// 统计粒度是进程；存在网页规则时浏览器整体算白名单进程，与 macOS 一致。
    public List<string> WhitelistAppIDs => Pages.Count == 0 ? [.. AppIDs.Order(StringComparer.Ordinal)] : [.. AppIDs.Union(BrowserCatalog.ProcessIDs).Order(StringComparer.Ordinal)];

    public bool Allows(string appID, string? url = null)
    {
        if (string.IsNullOrWhiteSpace(appID)) return false;
        if (BrowserCatalog.IsOwn(appID)) return true;
        if (BrowserCatalog.IsBrowser(appID)) return url is not null && Pages.Any(x => x.Matches(url));
        return AppIDs.Contains(appID);
    }
}

/// 已知的 Windows 浏览器进程。AppID 统一用「进程名 + .exe」，与 ForegroundAppService 保持一致。
public static class BrowserCatalog
{
    public static readonly string[] ProcessIDs =
    [
        "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "opera_gx.exe",
        "vivaldi.exe", "zen.exe", "waterfox.exe", "librewolf.exe", "floorp.exe", "arc.exe",
    ];

    public static bool IsBrowser(string? appID) => appID is not null && ProcessIDs.Contains(appID.Trim().ToLowerInvariant());

    /// 番茄小记自己永远放行。macOS 用 bundleID 前缀判断，Windows 用进程名。
    public static bool IsOwn(string? appID) => string.Equals(appID?.Trim(), "tomatonotes.exe", StringComparison.OrdinalIgnoreCase);
}

/// 守护当前盯着的对象：一个前台进程，浏览器再附带当前网页。
public sealed record GuardTarget(string AppID, string AppName, string WindowTitle, string? Url, string? PageTitle)
{
    public bool IsBrowser => BrowserCatalog.IsBrowser(AppID);

    /// 隐私窗口不判定也不关闭：读不到也不该读其中的内容。
    public bool IsPrivate => ContainsPrivateMarker(WindowTitle) || ContainsPrivateMarker(PageTitle);

    public string? PageKey => Url is null ? null : FocusPageRule.PageKey(Url);

    /// 浏览器要拿到可归一化的网址才够具体；其他进程至少有窗口标题才有判断依据。
    public bool MayAssess => !IsPrivate && (IsBrowser ? PageKey is not null : !string.IsNullOrWhiteSpace(WindowTitle));

    /// 停留计时的身份：浏览器精确到网页，其他进程按进程算。返回 null 表示在白名单内、不计时。
    public string? Identity(bool allowed)
    {
        if (allowed) return null;
        if (IsBrowser) return PageKey is null ? AppID : "page:" + PageKey;
        return AppID;
    }

    /// 交给 AI 的简短描述，只包含进程名与标题，不含窗口句柄等本机信息。
    public string Describe()
    {
        var title = IsBrowser ? PageTitle : WindowTitle;
        var text = string.IsNullOrWhiteSpace(AppName) ? AppID : AppName;
        if (!string.IsNullOrWhiteSpace(title)) text += " · " + Truncate(title.Trim(), 160);
        if (IsBrowser && PageKey is { } key) text += " · " + Truncate(key, 300);
        return Truncate(text, 500);
    }

    private static bool ContainsPrivateMarker(string? text)
    {
        if (string.IsNullOrEmpty(text)) return false;
        string[] markers = ["inprivate", "incognito", "无痕", "隐私窗口", "私有浏览", "private window", "privatmodus"];
        return markers.Any(m => text.Contains(m, StringComparison.OrdinalIgnoreCase));
    }

    private static string Truncate(string value, int limit) => value.Length <= limit ? value : value[..limit];
}

public enum GuardAction { None, Remind, Assess }

/// 停留计时状态机，与 macOS 的 GuardDwellMonitor 一致：
/// 身份变化或心跳中断超过 8 秒即重新计时；先提醒，再等宽限期，且每段身份只判定一次。
public struct GuardDwellMonitor
{
    public string? Identity { get; private set; }
    private double? beganAt;
    private double? remindedAt;
    private double? lastTick;
    private bool assessed;

    public void Reset() { this = default; }

    public GuardAction Update(string? next, double uptime, FocusGuardSettings settings, bool mayAssess)
    {
        if (next is null || !double.IsFinite(uptime)) { Reset(); return GuardAction.None; }
        if (Identity != next || (lastTick is double previous && (uptime < previous || uptime - previous > 8)))
        {
            Identity = next; beganAt = uptime; remindedAt = null; assessed = false;
        }
        lastTick = uptime;
        if (remindedAt is null && uptime - (beganAt ?? uptime) >= Math.Max(5, settings.RemindAfterSeconds))
        {
            remindedAt = uptime;
            return GuardAction.Remind;
        }
        if (remindedAt is double reminded && !assessed && mayAssess && uptime - reminded >= Math.Max(5, settings.GraceSeconds))
        {
            assessed = true;
            return GuardAction.Assess;
        }
        return GuardAction.None;
    }
}

/// AI 的判定结果。与 macOS 的 FocusRelevance 一致：只有明确无关且高度确信时才允许关闭。
public static class FocusVerdict
{
    public const string Related = "related";
    public const string Unrelated = "unrelated";
    public const string Uncertain = "uncertain";
}

public sealed record FocusRelevance(string Verdict, double Confidence, string Reason)
{
    public bool PermitsClosing => Verdict == FocusVerdict.Unrelated
        && double.IsFinite(Confidence) && Confidence >= .9 && Confidence <= 1
        && !string.IsNullOrWhiteSpace(Reason);
}

public sealed record FocusAssessment(FocusRelevance Relevance, int InputTokens, int OutputTokens);

/// 是否把当前内容交给 AI 判断，以及判断结果能否触发关闭。
/// 判定与关闭是两件事：本轮授权关闭，或开启「AI 判断相关性」，都会发起判定；
/// 只有单独授权关闭且判定明确无关、高度确信时才动手。
public static class GuardAssessmentPolicy
{
    /// 每轮 AI 判定次数上限，与 macOS 的 maxChecks 夹取范围一致。
    public static int CheckLimit(FocusGuardSettings settings) => Math.Clamp(settings.MaxChecks, 1, 5);

    public static bool MayAssess(FocusGuardSettings settings, FocusGuardPlan plan, bool hasAPIKey, GuardTarget target, int checksUsed)
        => (plan.AllowAIClosing || settings.AIRelevance) && hasAPIKey && target.MayAssess && checksUsed < CheckLimit(settings);

    public static bool MayClose(FocusGuardPlan plan, FocusRelevance relevance) => plan.AllowAIClosing && relevance.PermitsClosing;
}

/// 关闭进程的安全边界：系统外壳、会话关键进程与本应用绝不触碰。
public static class GuardProcessPolicy
{
    private static readonly HashSet<string> NeverClose = new(StringComparer.OrdinalIgnoreCase)
    {
        "tomatonotes.exe", "explorer.exe", "csrss.exe", "wininit.exe", "winlogon.exe", "services.exe",
        "svchost.exe", "lsass.exe", "smss.exe", "dwm.exe", "fontdrvhost.exe", "sihost.exe",
        "taskhostw.exe", "ctfmon.exe", "conhost.exe", "searchhost.exe", "shellexperiencehost.exe",
        "startmenuexperiencehost.exe", "textinputhost.exe", "applicationframehost.exe",
        "systemsettings.exe", "wudfhost.exe", "lockapp.exe", "audiodg.exe", "registry",
        "memory compression", "system", "idle", "windowsterminal.exe", "cmd.exe",
        "powershell.exe", "powershell_ise.exe", "pwsh.exe", "msedgewebview2.exe", "runtimebroker.exe",
    };

    /// 只有能明确判定为普通桌面应用的进程才可以被关闭。
    public static bool MayClose(string? appID, string? imagePath)
    {
        if (string.IsNullOrWhiteSpace(appID)) return false;
        if (NeverClose.Contains(appID.Trim())) return false;
        // 系统目录下的可执行文件一律不动，避免误伤更新或服务组件。
        if (!string.IsNullOrWhiteSpace(imagePath))
        {
            var path = imagePath.Replace('/', '\\');
            if (path.StartsWith(@"C:\Windows\", StringComparison.OrdinalIgnoreCase)) return false;
        }
        return true;
    }
}
