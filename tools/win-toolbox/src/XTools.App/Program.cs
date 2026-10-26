using Velopack;

namespace XTools.App;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Velopack：安装、更新、卸载时会带特殊参数启动程序，这里处理完会直接退出
        VelopackApp.Build().Run();

        // 已经在运行时，通知它打开偏好设置后退出（同 Mac 版再次打开 xTools.app）
        using var instance = new SingleInstance();
        if (!instance.IsFirst)
        {
            instance.ActivateFirst();
            return;
        }

        System.Windows.Forms.Application.EnableVisualStyles();
        new XToolsApp(instance).Run();
    }
}

/// <summary>保证只运行一个 xTools：用命名互斥量判断，用命名事件通知已运行的那个</summary>
public sealed class SingleInstance : IDisposable
{
    private readonly Mutex _mutex;
    private readonly EventWaitHandle _activate = new(false, EventResetMode.AutoReset, @"Local\xTools.Activate");

    public bool IsFirst { get; }

    public SingleInstance()
    {
        _mutex = new Mutex(true, @"Local\xTools.SingleInstance", out var createdNew);
        IsFirst = createdNew;
    }

    public void ActivateFirst() => _activate.Set();

    /// <summary>在后台线程等通知，收到就回调（回调里自己切回界面线程）</summary>
    public void ListenForActivation(Action onActivate)
    {
        var thread = new Thread(() =>
        {
            while (_activate.WaitOne()) onActivate();
        }) { IsBackground = true, Name = "xTools.Activate" };
        thread.Start();
    }

    public void Dispose()
    {
        if (IsFirst) _mutex.ReleaseMutex();
        _mutex.Dispose();
        _activate.Dispose();
    }
}
