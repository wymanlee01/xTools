using System.Text.Json;
using System.Text.Json.Nodes;

namespace XTools.Core;

/// <summary>
/// 设置存储：一个 JSON 文件（%APPDATA%\xTools\settings.json），键名和 Mac 版一致（如 “general.autoCheckUpdates”）。
/// 模块用 Scoped("clipboard") 拿到带前缀的存储，键名自动变成 “clipboard.xxx”
/// </summary>
public sealed class SettingsStore
{
    private readonly Storage _storage;
    private readonly string _prefix;

    public SettingsStore(string filePath) : this(new Storage(filePath), "") { }

    private SettingsStore(Storage storage, string prefix)
    {
        _storage = storage;
        _prefix = prefix;
    }

    /// <summary>某个模块的设置，键名加上 “模块 id.” 前缀</summary>
    public SettingsStore Scoped(string moduleId) => new(_storage, $"{_prefix}{moduleId}.");

    public string GetString(string key, string defaultValue) =>
        Read(key) is JsonValue v && v.TryGetValue(out string? s) ? s : defaultValue;

    public bool GetBool(string key, bool defaultValue) =>
        Read(key) is JsonValue v && v.TryGetValue(out bool b) ? b : defaultValue;

    public double GetDouble(string key, double defaultValue) =>
        Read(key) is JsonValue v && v.TryGetValue(out double d) ? d : defaultValue;

    public int GetInt(string key, int defaultValue) =>
        Read(key) is JsonValue v && v.TryGetValue(out int i) ? i : defaultValue;

    /// <summary>快捷键：没设置过返回默认值；设置成“无”（空字符串）返回 null</summary>
    public Hotkey? GetHotkey(string key, Hotkey? defaultValue)
    {
        if (Read(key) is not JsonValue v || !v.TryGetValue(out string? text)) return defaultValue;
        return Hotkey.Parse(text);
    }

    public void Set(string key, string value) => Write(key, JsonValue.Create(value));
    public void Set(string key, bool value) => Write(key, JsonValue.Create(value));
    public void Set(string key, double value) => Write(key, JsonValue.Create(value));
    public void Set(string key, int value) => Write(key, JsonValue.Create(value));
    public void SetHotkey(string key, Hotkey? value) => Write(key, JsonValue.Create(value?.DisplayName ?? ""));

    public void Remove(string key) => Write(key, null);

    /// <summary>恢复默认：删掉本前缀下的所有键（根存储就是全部清空）</summary>
    public void Reset() => _storage.RemoveWhere(key => key.StartsWith(_prefix, StringComparison.Ordinal));

    private JsonNode? Read(string key) => _storage.Get(_prefix + key);

    private void Write(string key, JsonNode? value) => _storage.Set(_prefix + key, value);

    /// <summary>所有 Scoped 存储共用的文件和内容；每次修改立即写盘</summary>
    private sealed class Storage
    {
        private readonly string _path;
        private readonly JsonObject _root;
        private readonly Lock _lock = new();

        public Storage(string path)
        {
            _path = path;
            _root = Load(path);
        }

        public JsonNode? Get(string key)
        {
            lock (_lock) return _root[key]?.DeepClone();
        }

        public void Set(string key, JsonNode? value)
        {
            lock (_lock)
            {
                if (value is null) _root.Remove(key); else _root[key] = value;
                Save();
            }
        }

        public void RemoveWhere(Func<string, bool> match)
        {
            lock (_lock)
            {
                foreach (var key in _root.Select(p => p.Key).Where(match).ToList()) _root.Remove(key);
                Save();
            }
        }

        /// <summary>文件不存在或内容损坏时从空设置开始</summary>
        private static JsonObject Load(string path)
        {
            try
            {
                return File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject obj ? obj : new JsonObject();
            }
            catch (JsonException)
            {
                return new JsonObject();
            }
        }

        /// <summary>先写临时文件再替换，避免写到一半断电留下坏文件</summary>
        private void Save()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(_path))!);
            var temp = _path + ".tmp";
            File.WriteAllText(temp, _root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, _path, overwrite: true);
        }
    }
}
