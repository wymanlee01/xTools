/// 模块之间互相提供服务的地方
/// 例如贴图模块注册 PinService，截图模块按协议取用，二者互不 import
@MainActor
public final class ServiceRegistry {
    private var services: [ObjectIdentifier: Any] = [:]

    public init() {}

    public func register<T>(_ type: T.Type, _ service: T) {
        services[ObjectIdentifier(type)] = service
    }

    /// 取不到说明提供方模块没启用，调用方要能处理 nil
    public func resolve<T>(_ type: T.Type) -> T? {
        services[ObjectIdentifier(type)] as? T
    }
}
