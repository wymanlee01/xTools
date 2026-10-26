namespace XTools.Core;

/// <summary>修饰键，数值和 Win32 RegisterHotKey 的 MOD_* 一致</summary>
[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Win = 8,
}

/// <summary>
/// 全局快捷键：按键名 + 修饰键。存进设置时用显示名（如 “Ctrl+Shift+A”、“F1”），读回时解析
/// </summary>
public readonly record struct Hotkey(string Key, HotkeyModifiers Modifiers = HotkeyModifiers.None)
{
    /// <summary>支持的按键名 → Windows 虚拟键码</summary>
    public static readonly IReadOnlyDictionary<string, ushort> VirtualKeys = BuildVirtualKeys();

    /// <summary>虚拟键码，按键名不认识时为 null</summary>
    public ushort? VirtualKey => VirtualKeys.TryGetValue(Key, out var vk) ? vk : null;

    /// <summary>显示名：修饰键按 Ctrl、Alt、Shift、Win 的顺序，再接按键名</summary>
    public string DisplayName
    {
        get
        {
            var parts = new List<string>();
            if (Modifiers.HasFlag(HotkeyModifiers.Control)) parts.Add("Ctrl");
            if (Modifiers.HasFlag(HotkeyModifiers.Alt)) parts.Add("Alt");
            if (Modifiers.HasFlag(HotkeyModifiers.Shift)) parts.Add("Shift");
            if (Modifiers.HasFlag(HotkeyModifiers.Win)) parts.Add("Win");
            parts.Add(Key);
            return string.Join("+", parts);
        }
    }

    public override string ToString() => DisplayName;

    /// <summary>解析显示名；格式不对或按键不支持时返回 null</summary>
    public static Hotkey? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = text.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return null;
        var modifiers = HotkeyModifiers.None;
        foreach (var part in parts[..^1])
        {
            var modifier = part.ToLowerInvariant() switch
            {
                "ctrl" or "control" => HotkeyModifiers.Control,
                "alt" => HotkeyModifiers.Alt,
                "shift" => HotkeyModifiers.Shift,
                "win" => HotkeyModifiers.Win,
                _ => (HotkeyModifiers?)null,
            };
            if (modifier is null) return null;
            modifiers |= modifier.Value;
        }
        var key = VirtualKeys.Keys.FirstOrDefault(k => string.Equals(k, parts[^1], StringComparison.OrdinalIgnoreCase));
        return key is null ? null : new Hotkey(key, modifiers);
    }

    private static Dictionary<string, ushort> BuildVirtualKeys()
    {
        var keys = new Dictionary<string, ushort>();
        for (var i = 1; i <= 24; i++) keys[$"F{i}"] = (ushort)(0x70 + i - 1);   // VK_F1 = 0x70
        for (var c = 'A'; c <= 'Z'; c++) keys[c.ToString()] = c;                 // 字母键码就是大写字母
        for (var d = '0'; d <= '9'; d++) keys[d.ToString()] = d;                 // 数字键码就是数字字符
        keys["Space"] = 0x20;
        keys["PrintScreen"] = 0x2C;
        keys["Insert"] = 0x2D;
        keys["Delete"] = 0x2E;
        keys["Home"] = 0x24;
        keys["End"] = 0x23;
        keys["PageUp"] = 0x21;
        keys["PageDown"] = 0x22;
        keys["Left"] = 0x25;
        keys["Up"] = 0x26;
        keys["Right"] = 0x27;
        keys["Down"] = 0x28;
        return keys;
    }
}
