#if os(macOS)
import Distributed
import DistributedXPC
import Foundation

@available(macOS 15, *)
public extension Rime {
  /// 启动 launchd on-demand XPC 服务,以 `Rime` 为根 actor(永不返回)。
  ///
  /// 每个接入的客户端连接获得独立的 `Rime` 实例(§4.2),全部实例共享本进程内
  /// 唯一的 librime 引擎(§3.7)。引擎的 setup/initialize/部署由客户端驱动
  /// (蓝绿预热,§4.3):服务端不做引擎级准备——on-demand 服务的启动耗时受
  /// launchd 超时约束,部署放在服务路径之外正是蓝绿设计的核心收益。
  ///
  /// 等价于在可执行目标中 `distributedXPCMain(Rime.self,…)`,但宿主可执行文件
  /// 无需直接 import DistributedXPC。必须在主线程调用(通常位于 `@main` 的
  /// 同步入口);服务名由 launchd 配置(Info.plist 的 XPCService 声明)提供。
  ///
  /// - Parameters:
  ///   - peerCodeSigningRequirement: **内核强制**的代码签名要求,于每个 peer
  ///     激活前安装;签名不满足的 peer 被 XPC 直接丢弃(服务端表现为 peer
  ///     end),要求本身无法安装时拒绝该 peer 并回报 `onPeerReject`——校验
  ///     从不静默降级为无校验(阶段 4 接入点)。
  ///   - shouldAccept: peer 审计窗口(要求安装后、激活前),可检查
  ///     `connection.pid`/`euid`;返回 `false` 或抛错即拒绝(错误回报
  ///     `onPeerReject`)。设置 `peerCodeSigningRequirement` 后不得再经此
  ///     钩子安装同族要求(libxpc 对二次安装直接 trap)。
  ///   - onPeerAccept / onPeerEnd / onPeerReject: 接入/断开/拒绝审计回调。
  @MainActor
  static func serveXPC(
    peerCodeSigningRequirement: String? = nil,
    shouldAccept: (@Sendable (XPCConnection) throws -> Bool)? = nil,
    onPeerAccept: (@Sendable (XPCConnection) -> Void)? = nil,
    onPeerEnd: (@Sendable (XPCConnection) -> Void)? = nil,
    onPeerReject: (@Sendable (XPCConnection, (any Error)?) -> Void)? = nil
  ) -> Never {
    distributedXPCMain(
      Rime.self,
      peerCodeSigningRequirement: peerCodeSigningRequirement,
      shouldAccept: shouldAccept,
      onPeerAccept: onPeerAccept,
      onPeerEnd: onPeerEnd,
      onPeerReject: onPeerReject)
  }
}
#endif
