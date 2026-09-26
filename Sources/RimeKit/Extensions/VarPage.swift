// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation
import RimeC

/// varpage 动态页长:librime 的内置 selector 按 menu/page_size 整页推进,
/// 选键槽位也是页内相对——这与"页面由 UI 按实测宽度折行"的候选窗天然
/// 冲突。varpage 模块把页界决定权交给宿主:按键处理中同步询问 resolver
/// "下标 i 所在页是哪一页",宿主以 UI 测量出的行结构作答。
///
/// RimeKit 的封装形态 = 页界表(tile 表):宿主推入「各页起始绝对下标 +
/// 候选总数」,resolver 据此二分作答——不在按键路径上回环宿主(XPC 架构
/// 下按键事务本来就阻塞在宿主线程,回调回环是死锁结构)。页界表随每次
/// 布局重推,越界下标答"未知",模块自动退回内置算术(契约承诺的降级)。
///
/// 线程契约(头文件):resolver 在按键处理线程同步执行,禁止调用 librime
/// 变动型入口(process_key/highlight/select/set_option/set_property/
/// apply_schema);读候选列表允许。tile 表以锁保护——推送虽经 actor 串行
/// 域,resolver 却是从引擎内部直入的裸指针路径,不享隔离。
final class VarPageTileBox: @unchecked Sendable {
  private let lock = NSLock()
  private var starts: [Int] = []
  private var total = 0

  /// 重推页界表。`starts` 须严格递增;空表 = 任意下标都答"未知"(回退)。
  func update(starts: [Int], total: Int) {
    lock.lock()
    defer { lock.unlock() }
    self.starts = starts
    self.total = total
  }

  /// 解析下标所在页。表外下标返回 nil(模块退回内置算术)。
  func resolve(index: Int) -> (start: Int, length: Int)? {
    lock.lock()
    defer { lock.unlock() }
    guard !starts.isEmpty, index >= starts[0], index < total else { return nil }
    var low = 0
    var high = starts.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if starts[mid] <= index { low = mid } else { high = mid - 1 }
    }
    let end = low + 1 < starts.count ? starts[low + 1] : total
    return (starts[low], end - starts[low])
  }
}

/// varpage 模块 API 绑定与 resolver 的 C 桥。
///
/// user_data 所有权(头文件):模块只存不释;resolver 的安全窗口自会话
/// 销毁(或 clear_resolver)开启。RimeKit 侧 box 由 actor 字典强持有、
/// 随进程存活(会话数有界,与通知 handler 的 retired 模式同型)——不
/// 抢跑生命周期,零 use-after-free 面。
enum RimeVarPageModule {
  /// 对会话安装 resolver。模块不存在(librime 未编入 varpage)返回 false,
  /// 调用方应退化运行(内置分页)。
  static func installResolver(
    for sessionID: RimeSessionID, box: VarPageTileBox
  ) -> Bool {
    guard
      let api = rime_get_api()?.pointee.find_module?("varpage")?.pointee.get_api()
        .map({ UnsafeMutableRawPointer($0).assumingMemoryBound(to: RimeVarPageApi.self) }),
      let setResolver = api.pointee.set_resolver
    else {
      RimeLog.logger.error("varpage 模块不可用;页界回退内置 page_size 算术")
      return false
    }
    let context = Unmanaged.passUnretained(box).toOpaque()
    return setResolver(sessionID.rawValue, varPageResolverCallback, context)
  }

  /// 摘除 resolver(可选;会话销毁本会自动摘)。返回 false = 已无注册。
  static func clearResolver(for sessionID: RimeSessionID) -> Bool {
    guard
      let api = rime_get_api()?.pointee.find_module?("varpage")?.pointee.get_api()
        .map({ UnsafeMutableRawPointer($0).assumingMemoryBound(to: RimeVarPageApi.self) }),
      let clearResolver = api.pointee.clear_resolver
    else { return false }
    return clearResolver(sessionID.rawValue)
  }
}

/// C 回调(显式 @convention(c) 常量:Swift 6 顶层函数被推断 @Sendable,
/// 不能隐式转换为 C 函数指针)。无捕获;user_data = `passUnretained` 的
/// tile 表。同步、热路径——只做锁内二分。session 参数不用:box 本就
/// 按会话注册。
private let varPageResolverCallback: RimeVarPageResolver = { userData, _, index, page in
  guard let userData, let page else { return false }
  let box = Unmanaged<VarPageTileBox>.fromOpaque(userData).takeUnretainedValue()
  guard let answer = box.resolve(index: index) else { return false }
  // size_t 在 Apple 平台映射为 Int,无需转换。
  page.pointee.start = answer.start
  page.pointee.length = answer.length
  return true
}

extension RimeSession {
  /// 推送页界表:各页起始绝对下标(严格递增)+ 候选总数。首次调用即对
  /// 会话注册 resolver;空表 = 回退内置分页。
  public func updateVarPageTiles(starts: [Int], total: Int) throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageUpdateTiles(starts: starts, total: total, for: id)
    }
  }

  /// 摘除 resolver(此后该会话恒走内置分页)。
  public func clearVarPageResolver() throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageClear(for: id)
    }
  }
}
