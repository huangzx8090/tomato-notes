namespace TomatoNotes.Core;

public sealed record FocusHeatmapDay(string Day, DateTime Date, double Seconds, bool IsToday, bool IsFuture)
{
    public int Intensity
    {
        get
        {
            if (Seconds <= 0) return 0;
            if (Seconds < 1800) return 1;
            if (Seconds < 3600) return 2;
            return Seconds < 7200 ? 3 : 4;
        }
    }
}

public sealed record FocusHeatmapWeek(List<FocusHeatmapDay> Days)
{
    public string ID => Days.FirstOrDefault()?.Day ?? "";
}

public sealed record FocusHeatmapRange(
    List<FocusHeatmapWeek> Weeks, string StartDay, string EndDay, double TotalSeconds, int ActiveDays)
{
    /// pageOffset == 0 是包含本周的最近一页，正数逐页向过去移动；页面以完整自然周相接。
    public static FocusHeatmapRange Build(IEnumerable<FocusInterval> intervals, int weekCount, int pageOffset = 0, DateTime? today = null)
    {
        var count = Math.Max(1, weekCount);
        var offset = Math.Max(0, pageOffset);
        var dayStart = (today ?? DateTime.Now).Date;
        var daysSinceMonday = ((int)dayStart.DayOfWeek + 6) % 7;
        var rangeStart = dayStart.AddDays(-(daysSinceMonday + (offset * count + count - 1) * 7));
        var secondsByDay = intervals.GroupBy(x => x.LocalDay).ToDictionary(g => g.Key, g => g.Sum(x => x.Seconds));

        var weeks = new List<FocusHeatmapWeek>(count);
        double totalSeconds = 0;
        var activeDays = 0;
        for (var weekIndex = 0; weekIndex < count; weekIndex++)
        {
            var days = new List<FocusHeatmapDay>(7);
            for (var dayIndex = 0; dayIndex < 7; dayIndex++)
            {
                var date = rangeStart.AddDays(weekIndex * 7 + dayIndex);
                var key = date.ToString("yyyy-MM-dd");
                var isFuture = date > dayStart;
                var seconds = isFuture ? 0 : secondsByDay.GetValueOrDefault(key);
                days.Add(new(key, date, seconds, key == dayStart.ToString("yyyy-MM-dd"), isFuture));
                totalSeconds += seconds;
                if (seconds > 0) activeDays++;
            }
            weeks.Add(new(days));
        }
        return new(weeks, weeks[0].Days[0].Day, weeks[^1].Days[^1].Day, totalSeconds, activeDays);
    }
}
