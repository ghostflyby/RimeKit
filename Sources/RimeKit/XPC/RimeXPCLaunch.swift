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
  /// 等价于在可执行目标中 `distributedXPCMain(Rime.self)`,但宿主可执行文件
  /// 无需直接 import DistributedXPC。必须在主线程调用(通常位于 `@main` 的
  /// 同步入口);服务名由 launchd 配置(Info.plist 的 XPCService 声明)提供。
  ///
  /// - Parameter shouldAccept: peer 接入审计(连接方的 `pid`/`euid`),返回
  ///   `false` 即拒绝连接。阶段 4 的 code-signing requirement 需要在连接
  ///   激活前预处理,上游 `xpcMain` 暂未暴露该钩子,当前以 pid/euid 审计兜底。
  @MainActor
  static func serveXPC(
    shouldAccept: (@Sendable (_ pid: pid_t, _ euid: uid_t) -> Bool)? = nil
  ) -> Never {
    guard let shouldAccept else {
      // 无审计需求:与上游入口完全一致(每 peer 一个 Rime 实例,默认全接受)。
      distributedXPCMain(Rime.self)
    }
    // 分布式方法参数不可序列化、xpcMain 不暴露 shouldAccept,审计钩子只能
    // 在此手装:server 逐连接构造 + accept(与上游 distributedXPCMain 同型)。
    let server = XPCRootActorServer(Rime.self, shouldAccept: { connection in
      shouldAccept(connection.pid, connection.euid)
    })
    return xpcMain { server.accept($0) }
  }
}
#endif
