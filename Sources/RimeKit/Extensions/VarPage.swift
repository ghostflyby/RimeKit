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
  let sessionID: RimeSessionID
  private let lock = NSLock()
  /// 累积记录的行起点序列(宿主随渲染合并推送,严格递增)。
  private var starts: [Int] = []
  /// 实测包络终点(末行首 + 末行数)。
  private var total = 0
  /// 卷轴状态位(注册内状态):翻页动作在引擎侧查询时自行翻位,宿主
  /// 事务后回读跟随展开;不识别任何事件的 key code。
  private var open = false
  /// 上一查询的行起点:翻页动作 = 同一事务内两次落在**不同行**的查询
  /// (选中页 + 边界页);选中动作只查一次。据此识别「翻页」并触发
  /// 开卷轴。
  private var lastQueryStart: Int?

  init(sessionID: RimeSessionID) {
    self.sessionID = sessionID
  }

  /// 合并/覆盖累积序列与包络终点。保留位与查询识别状态(表更新不打断
  /// 翻页识别);换组字走 `reset`。
  func update(starts: [Int], total: Int) {
    lock.lock()
    defer { lock.unlock() }
    self.starts = starts
    self.total = total
  }

  func isOpen() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return open
  }

  /// 换组字重置:位闭、清序列与查询识别状态。
  func reset() {
    lock.lock()
    defer { lock.unlock() }
    starts = []
    total = 0
    open = false
    lastQueryStart = nil
  }

  /// 含 index 的行 [start, end)。
  private func rowRange(index: Int) -> (start: Int, end: Int)? {
    guard !starts.isEmpty, index >= starts[0], index < total else { return nil }
    var low = 0
    var high = starts.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if starts[mid] <= index { low = mid } else { high = mid - 1 }
    }
    let end = low + 1 < starts.count ? starts[low + 1] : total
    return (starts[low], end)
  }

  /// 查询下标所在页。表外下标 → nil(varpage 契约:整键回退内置算术)。
  ///
  /// 翻页识别状态机:翻页动作在同一事务内查询两次(选中页 + 边界页),
  /// 两次落在不同行;选中动作只查一次。第二次查询即判定翻页,位闭则置
  /// 卷轴位(宿主事务后回读展开)。**首翻页(前向)答原位**:上游
  /// librime ≥ 1.17.0-pack.9.1.0 允许翻页返回任意位置——对边界查询答
  /// 当前行,引擎 offset carry 的落点 = 原高亮,即「首翻页只展开、候选
  /// 不动」由答案本身实现(真正的不翻页)。曾以「延长当前行到边界」
  /// 作答,该页与网格表瓦片重叠:旧版遭防倒退拒答回落内置算术(高亮
  /// 跳一页)且引擎翻页状态被污染,已弃。后向首翻页照常答目标行。
  func page(of index: Int) -> (start: Int, length: Int)? {
    lock.lock()
    defer { lock.unlock() }
    guard let row = rowRange(index: index) else { return nil }
    let pageTurn = lastQueryStart != nil && lastQueryStart != row.start
    let previousStart = lastQueryStart
    lastQueryStart = row.start
    if pageTurn, !open {
      open = true
      if let previousStart, index > previousStart,
        let origin = rowRange(index: previousStart)
      {
        return (origin.start, origin.end - origin.start)
      }
    }
    return (row.start, row.end - row.start)
  }

  /// 事务边界:清翻页识别残留。跨事务的单次查询(选键等)会把下一事务
  /// 的首次查询误判为翻页第二段(误置卷轴位/误触原位答)。open 位不动。
  /// 由 keyTransaction 在 processKey 前调用。
  func beginTurnDetection() {
    lock.lock()
    defer { lock.unlock() }
    lastQueryStart = nil
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
  guard let answer = box.page(of: index) else { return false }
  // size_t 在 Apple 平台映射为 Int,无需转换。
  page.pointee.start = answer.start
  page.pointee.length = answer.length
  return true
}

extension RimeSession {
  /// 推送累积行起点序列(严格递增)+ 实测包络终点。首次调用即对会话
  /// 注册 resolver;空表 = 引擎侧翻页退回内置分页。
  public func updateVarPageTiles(starts: [Int], total: Int) throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageUpdateTiles(starts: starts, total: total, for: id)
    }
  }

  /// 回读卷轴位:翻页动作在引擎侧 resolver 翻位,宿主事务后读取跟随。
  public func varPageIsOpen() throws -> Bool {
    let root = self.root
    let id = self.id
    return try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageIsOpen(for: id)
    }
  }

  /// 换组字重置:位闭、清累积序列。
  public func varPageReset() throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageReset(for: id)
    }
  }

  /// 高亮指定候选(不选词):首翻页键「只展开不动候选」的回滚件。
  public func varPageHighlight(index: Int) throws {
    let root = self.root
    let id = self.id
    try RimeSync.perform(timeout: .seconds(10)) {
      try await root.varPageHighlight(index: index, for: id)
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
