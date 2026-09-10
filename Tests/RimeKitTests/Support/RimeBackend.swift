import Foundation

@testable import RimeKit

/// 测试后端:根 actor(`RimeServiceRoot`)的来源,即全部功能测试的注入接缝。
///
/// 测试体一律只面向 `bootstrapped()` 给出的环境(根引用 + 数据目录 + 通知日志),
/// 对"根是进程内实例还是远程代理"零感知——这正是蓝绿方案"四种形态调用点同构"的镜像:
/// 今天 `inProcess` 直通 `localShared`;阶段 3 接入 XPC 后,同一批测试经后端参数化
/// (工具链的 Swift Testing 暂无 `@Suite(arguments:)`,以 `RIMEKIT_TEST_BACKEND`
/// 环境变量选择,CI 矩阵逐后端跑)即可成为 remote 集成测试。
struct RimeBackend: Sendable {
  let name: String
  let makeRoot: @Sendable () async throws -> RimeServiceRoot

  /// 进程内后端:librime 是进程级单例(§0),全部调用必须收敛到唯一共享根 actor
  /// (§3.7 单一执行域)——进程内**不**按套件多实例化根,否则并行套件并发触达 librime
  /// 即 §2.6 所述数据竞争。"多实例"语义由 remote 后端承载:每环境一条连接,
  /// 每个服务进程内恰一个引擎(§1.3)。
  static let inProcess = RimeBackend(name: "inProcess") { RimeServiceRoot.localShared }

  /// 全部可用后端。remote(阶段 3)接入时追加:
  ///   static let remote = RimeBackend(name: "remote") {
  ///     let connection = XPCRootConnection(toService: bundleURL(ofService: "RimeService"))
  ///     return try await RimeServiceRoot.resolve(using: connection)
  ///   }
  static let all: [RimeBackend] = [.inProcess]

  /// 当前测试运行选择的后端(`RIMEKIT_TEST_BACKEND`,缺省 inProcess)。
  static var current: RimeBackend {
    get throws {
      let requested = ProcessInfo.processInfo.environment["RIMEKIT_TEST_BACKEND"] ?? "inProcess"
      guard let backend = all.first(where: { $0.name == requested }) else {
        throw RimeTestFailure(
          stage: "backend",
          detail: "未知后端 \(requested);可用: \(all.map(\.name).joined(separator: ", "))")
      }
      return backend
    }
  }
}

/// 测试基建自身的失败(bootstrap 未达可测状态等),detail 携带 librime 侧诊断。
struct RimeTestFailure: Error, CustomStringConvertible {
  let stage: String
  let detail: String

  var description: String { "RimeTestFailure[\(stage)]: \(detail)" }
}
