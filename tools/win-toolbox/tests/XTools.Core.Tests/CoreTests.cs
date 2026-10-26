using Xunit;
using XTools.Core;

namespace XTools.Core.Tests;

public class HotkeyTests
{
    [Fact]
    public void 显示名按固定顺序拼接修饰键()
    {
        var hotkey = new Hotkey("A", HotkeyModifiers.Shift | HotkeyModifiers.Control);
        Assert.Equal("Ctrl+Shift+A", hotkey.DisplayName);
        Assert.Equal("F1", new Hotkey("F1").DisplayName);
    }

    [Fact]
    public void 解析显示名并能来回转换()
    {
        Assert.Equal(new Hotkey("F3", HotkeyModifiers.Shift), Hotkey.Parse("shift + f3"));
        var hotkey = new Hotkey("PrintScreen", HotkeyModifiers.Alt | HotkeyModifiers.Win);
        Assert.Equal(hotkey, Hotkey.Parse(hotkey.DisplayName));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Ctrl+")]
    [InlineData("Hyper+A")]
    [InlineData("Ctrl+F25")]
    public void 格式不对返回null(string text) => Assert.Null(Hotkey.Parse(text));

    [Fact]
    public void 虚拟键码和Win32一致()
    {
        Assert.Equal((ushort)0x70, new Hotkey("F1").VirtualKey);
        Assert.Equal((ushort)0x75, new Hotkey("F6").VirtualKey);
        Assert.Equal((ushort)'A', new Hotkey("A").VirtualKey);
        Assert.Equal((ushort)0x2C, new Hotkey("PrintScreen").VirtualKey);
    }
}

public class SettingsStoreTests
{
    private static string TempFile() => Path.Combine(Path.GetTempPath(), $"xtools-tests-{Guid.NewGuid()}", "settings.json");

    [Fact]
    public void 读写各种类型并写盘()
    {
        var path = TempFile();
        var store = new SettingsStore(path);
        store.Set("general.autoCheckUpdates", false);
        store.Set("clipboard.limit", 300);
        store.Set("pin.opacity", 0.8);
        store.Set("general.skippedUpdateVersion", "0.2.0");

        var reopened = new SettingsStore(path);
        Assert.False(reopened.GetBool("general.autoCheckUpdates", true));
        Assert.Equal(300, reopened.GetInt("clipboard.limit", 0));
        Assert.Equal(0.8, reopened.GetDouble("pin.opacity", 1));
        Assert.Equal("0.2.0", reopened.GetString("general.skippedUpdateVersion", ""));
        Assert.True(reopened.GetBool("missing", true));
    }

    [Fact]
    public void 模块设置带前缀且重置只清自己()
    {
        var store = new SettingsStore(TempFile());
        var clipboard = store.Scoped("clipboard");
        clipboard.Set("limit", 100);
        store.Set("general.autoCheckUpdates", false);
        Assert.Equal(100, store.GetInt("clipboard.limit", 0));

        clipboard.Reset();
        Assert.Equal(300, clipboard.GetInt("limit", 300));
        Assert.False(store.GetBool("general.autoCheckUpdates", true));
    }

    [Fact]
    public void 快捷键区分没设置和设置成无()
    {
        var store = new SettingsStore(TempFile());
        var fallback = new Hotkey("F1");
        Assert.Equal(fallback, store.GetHotkey("hotkey.capture", fallback));
        store.SetHotkey("hotkey.capture", null);
        Assert.Null(store.GetHotkey("hotkey.capture", fallback));
        store.SetHotkey("hotkey.capture", new Hotkey("A", HotkeyModifiers.Control));
        Assert.Equal(new Hotkey("A", HotkeyModifiers.Control), store.GetHotkey("hotkey.capture", fallback));
    }

    [Fact]
    public void 文件损坏时从空设置开始()
    {
        var path = TempFile();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{ 坏掉的 json");
        var store = new SettingsStore(path);
        Assert.Equal(5, store.GetInt("any", 5));
        store.Set("any", 1);
        Assert.Equal(1, new SettingsStore(path).GetInt("any", 5));
    }
}

public class ServiceRegistryTests
{
    private interface IGreeter { string Hello(); }
    private sealed class Greeter : IGreeter { public string Hello() => "hi"; }

    [Fact]
    public void 按接口注册和取用()
    {
        var registry = new ServiceRegistry();
        Assert.Null(registry.Resolve<IGreeter>());
        registry.Register<IGreeter>(new Greeter());
        Assert.Equal("hi", registry.Resolve<IGreeter>()?.Hello());
    }
}
