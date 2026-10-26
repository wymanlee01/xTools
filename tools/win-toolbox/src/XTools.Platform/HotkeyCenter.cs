using System.Runtime.InteropServices;
using System.Windows.Interop;
using XTools.Core;

namespace XTools.Platform;

/// <summary>快捷键已被其他程序占用等原因注册失败</summary>
public sealed class HotkeyException(string message) : Exception(message);

/// <summary>
/// 全局快捷键：用一个看不见的消息窗口接收 WM_HOTKEY（同 Mac 版用 Carbon RegisterEventHotKey）。
/// 按模块 id 记录注册的快捷键，模块停用或改设置时整批注销
/// </summary>
public sealed partial class HotkeyCenter : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const uint ModNoRepeat = 0x4000;   // 按住不放时不重复触发

    private readonly HwndSource _window;
    private readonly Dictionary<int, (string Owner, Action Action)> _registered = new();
    private int _nextId = 1;

    public HotkeyCenter()
    {
        // 父窗口设成 HWND_MESSAGE（-3）：只收消息，不显示、不进任务栏
        _window = new HwndSource(new HwndSourceParameters("xTools.Hotkeys") { ParentWindow = new IntPtr(-3) });
        _window.AddHook(WndProc);
    }

    /// <summary>注册快捷键，失败（被占用、按键不支持）时抛 HotkeyException</summary>
    public void Register(Hotkey hotkey, string owner, Action action)
    {
        if (hotkey.VirtualKey is not { } vk) throw new HotkeyException($"不支持的按键：{hotkey.Key}");
        var id = _nextId++;
        if (!RegisterHotKey(_window.Handle, id, (uint)hotkey.Modifiers | ModNoRepeat, vk))
            throw new HotkeyException($"快捷键 {hotkey.DisplayName} 已被其他程序占用");
        _registered[id] = (owner, action);
    }

    /// <summary>注销某个模块注册的全部快捷键</summary>
    public void UnregisterAll(string owner)
    {
        foreach (var id in _registered.Where(p => p.Value.Owner == owner).Select(p => p.Key).ToList())
        {
            UnregisterHotKey(_window.Handle, id);
            _registered.Remove(id);
        }
    }

    public void Dispose()
    {
        foreach (var id in _registered.Keys) UnregisterHotKey(_window.Handle, id);
        _registered.Clear();
        _window.Dispose();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey && _registered.TryGetValue(wParam.ToInt32(), out var entry))
        {
            entry.Action();
            handled = true;
        }
        return IntPtr.Zero;
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterHotKey(IntPtr hWnd, int id);
}
