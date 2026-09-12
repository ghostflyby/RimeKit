// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
  import Distributed
  import DistributedXPC
  import Foundation

  @available(macOS 15, *)
  extension Rime {
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
    public static func serveXPC(
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

    /// 连接 launchd on-demand 的 Rime XPC 服务并解析根 actor(消费侧入口)。
    ///
    /// 与 `serveXPC` 对称:客户端无需直接 import DistributedXPC。连接具备
    /// 重连语义(named mach service):服务重启后,对返回根 actor 的调用
    /// 透明恢复。
    ///
    /// - Parameters:
    ///   - serviceName: launchd mach service 名,须与服务端一致(由宿主
    ///     自行约定,如 bundle id 派生)。
    ///   - peerCodeSigningRequirement: **内核强制**的代码签名要求,于连接
    ///     激活前安装;服务不满足即被 XPC 丢弃,要求无法安装时抛错
    ///     (fail-closed),从不静默降级为无校验。
    public static func connect(
      toService serviceName: String,
      peerCodeSigningRequirement: String? = nil
    ) throws -> Rime {
      try Self.connectViaXPCRoot(
        toService: serviceName, peerCodeSigningRequirement: peerCodeSigningRequirement)
    }

    /// 泛型形参语境下成员查找只可见协议扩展成员,不会递归命中本体。
    private static func connectViaXPCRoot<A: XPCRootActor>(
      toService serviceName: String,
      peerCodeSigningRequirement: String?
    ) throws -> A {
      try A.connect(
        toService: serviceName,
        peerCodeSigningRequirement: peerCodeSigningRequirement)
    }

    /// 返回服务进程 pid。宿主蓝绿切换协议:shutdown 前记下 pid,shutdown 后
    /// 轮询其消失,以确认 userdb 锁已释放。
    public distributed func servicePid() async throws(RimeError) -> pid_t {
      pid_t(getpid())
    }

    /// 请求服务进程干净退出(蓝绿切换协议:宿主应先 syncUserData 落盘)。
    ///
    /// RPC 应答可能随进程终止而失败,调用方应容忍错误并以 servicePid 消失
    /// 为完成标志。exit(0) 不运行 librime 级清理,但 leveldb WAL 保证重开
    /// 一致性。
    public distributed func shutdown() async throws(RimeError) {
      Foundation.exit(0)
    }
  }
#endif
