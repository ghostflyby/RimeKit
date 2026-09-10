// RimeService.blue:XPC 服务入口(launchd on-demand,§4.1)。
// 与 green 共享同一实现,仅 bundle id 不同——蓝绿双槽(§4.3)。

import RimeKit

// xpc_main 要求主线程;main.swift 顶层代码即主线程,assumeIsolated 进入
// @MainActor 的 serveXPC(永不返回)。
MainActor.assumeIsolated {
    Rime.serveXPC()
}
