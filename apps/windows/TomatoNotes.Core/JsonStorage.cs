using System.Text.Json;
using System.Text.Json.Serialization;

namespace TomatoNotes.Core;

/// <summary>Foundation JSONEncoder's default date is seconds since 2001-01-01 UTC.</summary>
public sealed class AppleDateConverter : JsonConverter<DateTimeOffset>
{
    private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.TokenType switch
    {
        JsonTokenType.Number => Epoch.AddSeconds(reader.GetDouble()),
        JsonTokenType.String when DateTimeOffset.TryParse(reader.GetString(), out var date) => date,
        _ => throw new JsonException("无法读取日期。")
    };
    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) => writer.WriteNumberValue((value - Epoch).TotalSeconds);
}
public sealed class NullableAppleDateConverter : JsonConverter<DateTimeOffset?>
{
    private static readonly AppleDateConverter Inner = new();
    public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.TokenType == JsonTokenType.Null ? null : Inner.Read(ref reader, typeof(DateTimeOffset), options);
    public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options) { if (value.HasValue) Inner.Write(writer, value.Value, options); else writer.WriteNullValue(); }
}
public static class TomatoJson
{
    public static JsonSerializerOptions Options { get; } = Create();
    private static JsonSerializerOptions Create()
    {
        var options = new JsonSerializerOptions { WriteIndented = true, AllowTrailingCommas = true, ReadCommentHandling = JsonCommentHandling.Skip };
        options.Converters.Add(new AppleDateConverter()); options.Converters.Add(new NullableAppleDateConverter());
        return options;
    }
}

public sealed class LocalRepository : IDisposable
{
    private readonly FileStream? lockStream;
    public string Root { get; }
    public string FilePath { get; }
    public bool IsSharedLibrary { get; }
    public string AttachmentsPath => Path.Combine(Root, "Attachments");
    public bool CanWrite { get; set; } = true;
    public string? LoadError { get; set; }

    public LocalRepository(string? root = null, bool takeLock = true)
    {
        Root = Path.GetFullPath(root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TomatoNotes"));
        IsSharedLibrary = root is null;
        FilePath = Path.Combine(Root, "data.json");
        Directory.CreateDirectory(Root);
        if (takeLock)
        {
            try { lockStream = new FileStream(Path.Combine(Root, ".tomato-notes.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); lockStream.SetLength(0); using var writer = new StreamWriter(lockStream, leaveOpen: true); writer.Write(Environment.ProcessId); writer.Flush(); }
            catch (IOException) { throw new InvalidOperationException("这份数据已由另一个番茄小记进程打开。"); }
        }
    }
    public AppData Load()
    {
        if (!File.Exists(FilePath)) return new();
        try
        {
            var data = JsonSerializer.Deserialize<AppData>(File.ReadAllText(FilePath), TomatoJson.Options) ?? throw new JsonException("资料为空");
            if (data.SchemaVersion is < 1 or > 4) throw new InvalidDataException($"当前应用不支持数据版本 {data.SchemaVersion}；原始数据未改动。");
            if (data.SchemaVersion < 4) { Backup($"schema-v{data.SchemaVersion}"); data.SchemaVersion = 4; }
            return data;
        }
        catch (Exception ex) when (ex is JsonException or IOException or InvalidDataException or UnauthorizedAccessException)
        { CanWrite = false; LoadError = ex.Message; return new(); }
    }
    public void Save(AppData data)
    {
        if (!CanWrite) throw new InvalidOperationException("原始资料读取失败，已禁止覆盖。请先备份并检查数据文件。");
        Directory.CreateDirectory(Root);
        var json = JsonSerializer.Serialize(data, TomatoJson.Options);
        var temporary = Path.Combine(Root, $".data-{Guid.NewGuid():N}.tmp");
        try { using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { using var writer = new StreamWriter(stream); writer.Write(json); writer.Flush(); stream.Flush(true); } File.Move(temporary, FilePath, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public string? Backup(string? folder = null)
    {
        if (!File.Exists(FilePath)) return null;
        var root = Path.Combine(Root, "Backups", folder ?? "");
        Directory.CreateDirectory(root);
        var destination = Path.Combine(root, $"data-{DateTime.Now:yyyy-MM-ddTHH-mm-ss}-{Guid.NewGuid().ToString()[..8]}.json");
        File.Copy(FilePath, destination);
        if (Directory.Exists(AttachmentsPath))
        {
            var assets = Path.ChangeExtension(destination, ".assets") + Path.DirectorySeparatorChar + "Attachments";
            Directory.CreateDirectory(assets);
            foreach (var file in Directory.EnumerateFiles(AttachmentsPath)) File.Copy(file, Path.Combine(assets, Path.GetFileName(file)), false);
        }
        return destination;
    }
    public void Dispose() { lockStream?.Dispose(); GC.SuppressFinalize(this); }
}
