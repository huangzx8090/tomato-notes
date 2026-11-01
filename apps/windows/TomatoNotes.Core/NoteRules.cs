namespace TomatoNotes.Core;

/// 便签的纯规则，供界面与测试共用。
public static class NoteRules
{
    /// 「最近便签」快捷键的目标：今天最近更新的一张；当天没有便签时返回 null，由调用方新建。
    /// 与 macOS NoteWindows.openRecent 一致，不复制历史原稿。
    public static StickyNote? RecentToday(IEnumerable<StickyNote> notes, string today)
        => notes.Where(x => x.DayKey == today)
            .OrderByDescending(x => x.UpdatedAt)
            // 与 macOS NoteLibrary.sorted 一致：更新时间相同时按 UUID 字符串排序。
            .ThenBy(x => x.ID.ToString())
            .FirstOrDefault();
}
