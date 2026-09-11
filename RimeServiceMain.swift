// RimeService.blue / RimeService.green 共享的 XPC 服务入口(§4.1)。
// 两 target 仅 bundle id 不同(blue/green 双槽),入口实现完全一致。
// launchd 主线程语义由 @MainActor 保证;serveXPC 永不返回(§4.3)。

import RimeKit

@main
@MainActor
struct ServiceMain {
    static func main() {
        Rime.serveXPC()
    }
}
