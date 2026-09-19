// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// XPC 服务入口(SwiftXPC 0.6 XPCApp 模式):类型即委托,库提供的 main()
// 托管 XPCServiceHost 服务 Rime.shared;协作式关闭后进程退役。

import DistributedXPC
import RimeKit

@main
struct PteromyiniRimeService: XPCApp {
  typealias Root = Rime
}
