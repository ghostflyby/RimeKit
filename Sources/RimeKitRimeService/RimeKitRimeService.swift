// RimeKit XPC 服务可执行目标(rimed):launchd on-demand 入口(§4.1)。
// 同一二进制部署为 RimeService.blue.xpc / RimeService.green.xpc 两个 bundle id。
// iOS 构建下本目标为空壳(包内守护:仅 macOS 有 XPC,§2.5)。

#if os(macOS)
import RimeKit

@main
@MainActor
struct RimeKitRimeService {
  static func main() {
    Rime.serveXPC()
  }
}
#else
@main
struct RimeKitRimeService {
  static func main() {}
}
#endif
