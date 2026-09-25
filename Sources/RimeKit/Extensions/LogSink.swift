import Foundation
import RimeC
import os

/// librime glog 转接目标。默认 librime 专属 subsystem(跨蓝绿代次稳定);
/// 宿主可在 librime 初始化前替换为自身 subsystem 并入统一检索。
public enum RimeLog {
  public nonisolated(unsafe) static var logger = Logger(
    subsystem: "dev.ghostflyby.rime", category: "librime")
}

/// librime logsink 安装与配置:把 glog 记录转发到 `RimeLog.logger` 并可
/// 静音 stderr。模块构造器注册先于 setup,`install()` 在任意阶段可调用
/// (越早安装,能捕获的组件注册/部署日志越全);幂等(同一 context)。
///
/// 回调约束(头文件):在日志调用线程上运行、可能并发;不得回逆进入
/// librime 日志(同步 LOG 带锁重入死锁)、不得在回调内调
/// set_stderr_threshold;保持短小——os.Logger 满足全部约束。
///
/// 隐私:glog INFO+ 为引擎内部诊断(部署/字典/Lua),按宿主约定以
/// public 落统一日志;键入内容仅存在于更低 VERBOSE 档,不进本通道。
public enum RimeLogSink {
  /// 安装转发 sink 并静音 stderr。幂等(add_sink 对同一 context 返回
  /// false 无副作用)。
  public static func install(rimeApi: RimeApi) {
    guard
      let logsink = rimeApi.find_module?("logsink")?
        .pointee.get_api()
        .map({ UnsafeMutableRawPointer($0).assumingMemoryBound(to: RimeLogSinkApi.self) })
    else {
      RimeLog.logger.error("logsink module unavailable; glog 维持文件/stderr 现状")
      return
    }
    logsink.pointee.set_stderr_threshold(RimeLogSinkThreshold.silent)
    logsink.pointee.add_sink(nil, rimeLogSinkCallback)
  }

  /// 便捷重载:内部取 rime_get_api()。
  public static func install() {
    install(rimeApi: rime_get_api().pointee)
  }
}

/// C 回调:无捕获(可作 C 函数指针);context 为注册标识(恒 nil),此处
/// 无需状态。
private func rimeLogSinkCallback(
  _ context: UnsafeMutableRawPointer?, _ record: UnsafePointer<rime_logsink_record>?
) {
  guard let record else { return }
  let r = record.pointee

  let message: String
  if let ptr = r.message {
    let data = Data(bytes: ptr, count: r.message_length)
    message =
      String(data: data, encoding: .utf8)
      ?? "(非 UTF8 rime 日志 \(r.message_length) 字节)"
  } else {
    message = "(empty)"
  }
  let file = r.base_filename.map { String(cString: $0) } ?? "?"

  let level: OSLogType
  switch r.severity {
  case .info: level = .info
  case .warning: level = .default
  case .error: level = .error
  case .fatal: level = .fault
  @unknown default: level = .default
  }

  RimeLog.logger.log(
    level: level,
    "[\(file, privacy: .public):\(r.line, privacy: .public)] \(message, privacy: .public)"
  )
}

/// librime ERROR 及以上记录的进程内收集器,经 `RimeLogSink.installErrorCollector()`
/// 安装。部署与配置 link 的多数失败只出现在 glog 记录里(返回值仍为成功),
/// 收集器是把这类失败变成可编程判据的通道。
///
/// 回调约束同转发 sink(在日志调用线程上运行、可能并发;不得回逆进入
/// librime 日志):内部只做加锁赋值。
public final class RimeLogErrorCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var first: String?
  private var installed = true

  /// 首条 ERROR 及以上记录,格式 `[文件:行] 内容`;尚无记录时为 nil。
  public var firstError: String? {
    lock.lock()
    defer { lock.unlock() }
    return first
  }

  func record(_ message: String) {
    lock.lock()
    defer { lock.unlock() }
    if first == nil { first = message }
  }

  /// 摘除 sink。幂等;摘除后收集器停止更新。不摘除则随进程存活——与转发
  /// sink 的常驻语义一致。
  public func uninstall() {
    lock.lock()
    defer { lock.unlock() }
    guard installed else { return }
    installed = false
    if let api = rime_get_api()?.pointee.find_module?("logsink")?.pointee.get_api() {
      let sinkAPI = UnsafeMutableRawPointer(api)
        .assumingMemoryBound(to: RimeLogSinkApi.self)
      _ = sinkAPI.pointee.remove_sink?(Unmanaged.passUnretained(self).toOpaque())
    }
    Unmanaged.passUnretained(self).release()
  }
}

extension RimeLogSink {
  /// 安装一个只收集 ERROR 及以上记录的 sink,返回收集器;本 librime 不含
  /// logsink 模块(系统或第三方构建可缺)或注册失败时返回 nil,此时上述失败
  /// 无从观察,调用方应退化为只检查产物。
  ///
  /// 与 `install()` 正交:转发走转发,sink 可多路注册;本方法不触碰 stderr
  /// 阈值。安装即持有收集器(uninstall 时释放),提前丢弃引用不影响安全。
  public static func installErrorCollector() -> RimeLogErrorCollector? {
    guard
      let logsink = rime_get_api()?.pointee.find_module?("logsink")?.pointee.get_api()
        .map({ UnsafeMutableRawPointer($0).assumingMemoryBound(to: RimeLogSinkApi.self) }),
      let addSink = logsink.pointee.add_sink
    else { return nil }

    let collector = RimeLogErrorCollector()
    let context = Unmanaged.passRetained(collector).toOpaque()
    guard addSink(context, rimeErrorCollectorCallback) else {
      Unmanaged.passUnretained(collector).release()
      return nil
    }
    return collector
  }
}

/// C 回调:无捕获(可作 C 函数指针);context 为 `passRetained` 的收集器。
private func rimeErrorCollectorCallback(
  _ context: UnsafeMutableRawPointer?, _ record: UnsafePointer<rime_logsink_record>?
) {
  guard let context, let record else { return }
  let r = record.pointee
  guard r.severity == .error || r.severity == .fatal else { return }

  let message: String
  if let ptr = r.message {
    message =
      String(
        decoding: UnsafeRawBufferPointer(start: ptr, count: r.message_length),
        as: UTF8.self)
  } else {
    message = "(empty)"
  }
  let location = r.base_filename.map { "[\(String(cString: $0)):\(r.line)] " } ?? ""

  Unmanaged<RimeLogErrorCollector>.fromOpaque(context)
    .takeUnretainedValue()
    .record(location + message)
}
