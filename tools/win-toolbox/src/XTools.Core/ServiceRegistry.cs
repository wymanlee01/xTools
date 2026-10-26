namespace XTools.Core;

/// <summary>
/// 模块之间协作用的服务表：提供方注册接口实现，使用方按接口取用（同 Mac 版 ServiceRegistry），
/// 这样功能模块之间不用互相引用
/// </summary>
public sealed class ServiceRegistry
{
    private readonly Dictionary<Type, object> _services = new();

    public void Register<T>(T service) where T : class => _services[typeof(T)] = service;

    public T? Resolve<T>() where T : class => _services.TryGetValue(typeof(T), out var service) ? (T)service : null;
}
