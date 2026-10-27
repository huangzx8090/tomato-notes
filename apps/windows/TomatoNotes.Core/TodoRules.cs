namespace TomatoNotes.Core;

public enum TodoCarryoverUndoResult { Undone, Missing, NotScheduledToday, Completed }

/// 待办顺延的纯规则。日期键使用项目既有的 yyyy-MM-dd 格式，因此可按字符串排序。
public static class TodoCarryover
{
    public static List<TodoItem> Candidates(IEnumerable<TodoItem> todos, string today)
        => todos.Where(x => !x.IsCompleted && string.CompareOrdinal(x.LocalDay, today) < 0
                       && string.CompareOrdinal(x.EffectiveScheduledDay, today) < 0)
            .OrderBy(x => x.EffectiveScheduledDay, StringComparer.Ordinal)
            .ThenBy(x => x.CreatedAt)
            .ThenBy(x => x.ID, GuidComparer.Instance)
            .ToList();

    public static bool Schedule(Guid id, string day, IList<TodoItem> todos)
    {
        var index = Find(todos, id);
        if (index is null) return false;
        var todo = todos[index.Value];
        if (todo.IsCompleted
            || string.CompareOrdinal(todo.LocalDay, day) >= 0
            || string.CompareOrdinal(todo.EffectiveScheduledDay, day) >= 0
            || todo.IsScheduledOn(day)) return false;

        todo.ScheduledDays = todo.ScheduledDays.Count == 0 ? [todo.LocalDay] : [.. todo.ScheduledDays];
        if (!todo.ScheduledDays.Contains(todo.LocalDay)) todo.ScheduledDays.Insert(0, todo.LocalDay);
        if (todo.ScheduledDays.Contains(day)) return false;
        todo.ScheduledDays.Add(day);
        return true;
    }

    public static List<Guid> Schedule(IEnumerable<Guid> ids, string day, IList<TodoItem> todos)
    {
        var selected = ids.ToHashSet();
        var changed = new List<Guid>();
        foreach (var id in Candidates(todos, day).Select(x => x.ID).Where(selected.Contains))
            if (Schedule(id, day, todos)) changed.Add(id);
        return changed;
    }

    public static TodoCarryoverUndoResult UndoSchedule(Guid id, string day, IList<TodoItem> todos)
    {
        var index = Find(todos, id);
        if (index is null) return TodoCarryoverUndoResult.Missing;
        var todo = todos[index.Value];
        if (todo.IsCompleted) return TodoCarryoverUndoResult.Completed;
        if (day == todo.LocalDay || !todo.ScheduledDays.Contains(day))
            return TodoCarryoverUndoResult.NotScheduledToday;

        todo.ScheduledDays = todo.ScheduledDays.Where(x => x != day).ToList();
        if (!todo.ScheduledDays.Contains(todo.LocalDay)) todo.ScheduledDays.Insert(0, todo.LocalDay);
        return TodoCarryoverUndoResult.Undone;
    }

    private static int? Find(IList<TodoItem> todos, Guid id)
    {
        for (var index = 0; index < todos.Count; index++)
            if (todos[index].ID == id) return index;
        return null;
    }
}

internal sealed class GuidComparer : IComparer<Guid>
{
    public static readonly GuidComparer Instance = new();
    public int Compare(Guid x, Guid y) => string.CompareOrdinal(x.ToString(), y.ToString());
}

/// 删除历史只保存在本次运行内；恢复原记录，避免把撤销记成一次新的成果。
public sealed class TodoDeletionHistory
{
    private readonly List<(TodoItem Item, int Index)> entries = [];
    public TodoItem? LastDeleted => entries.Count == 0 ? null : entries[^1].Item;

    public bool Remove(Guid id, string day, IList<TodoItem> todos)
    {
        var index = Find(todos, id, day);
        if (index is null) return false;
        entries.Add((todos[index.Value], index.Value));
        todos.RemoveAt(index.Value);
        return true;
    }

    public TodoItem? RestoreLast(IList<TodoItem> todos)
    {
        if (entries.Count == 0) return null;
        var entry = entries[^1];
        entries.RemoveAt(entries.Count - 1);
        if (todos.Any(x => x.ID == entry.Item.ID)) return null;
        todos.Insert(Math.Min(entry.Index, todos.Count), entry.Item);
        return entry.Item;
    }

    public void Discard() => entries.Clear();

    private static int? Find(IList<TodoItem> todos, Guid id, string day)
    {
        for (var index = 0; index < todos.Count; index++)
            if (todos[index].ID == id && todos[index].EffectiveScheduledDay == day) return index;
        return null;
    }
}
