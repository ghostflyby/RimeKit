import Foundation
import RimeC
import os

/// 一条日志记录:字段与 librime `rime_logsink_record` 对应(指针已拷为
/// Swift 值);散点错误路径的字段语义见各属性。
public struct RimeLogRecord: Sendable {
  /// glog 四档(info/warning/error/fatal)。
  public let level: RimeLogLevel
  /// 纯文本消息(位置不内嵌)。
  public let message: String
  /// glog 转发=librime 源文件短名(如 "selector.cc",缺失为 nil);散点
  /// 错误=Swift 调用点 fileID。
  public let file: String?
  /// 调用点写的原始路径(通常为构建期相对形式);散点错误为 nil。
  public let fullFilename: String?
  /// 记录行号;散点错误为调用点行号。
  public let line: Int
  /// 毫秒 Unix 时间戳(UTC);散点错误为分发时刻。
  public let unixTimeMillis: Int64
  /// 记录时刻的本地时区偏移(秒)。
  public let utcOffsetSeconds: Int
}

/// 宿主注册的分级回调:落盘形态完全由回调决定,库不引入任何日志依赖;
/// 未注册时记录丢弃。
public typealias RimeLogHandler = @Sendable (_ record: RimeLogRecord) -> Void

public enum RimeLog {
  private static let storage = OSAllocatedUnfairLock<RimeLogHandler?>(initialState: nil)

  /// 注册分级日志回调。应在引擎 setup 前注册(set/install 顺序无关);
  /// 重复注册以后一次为准,传 nil 摘除。
  public static func set(handler: RimeLogHandler?) {
    storage.withLock { $0 = handler }
  }

  /// 分发一条记录到当前回调(模块内:glog 转发回调)。
  static func emit(_ record: RimeLogRecord) {
    storage.withLock { $0 }?(record)
  }

  /// 散点错误路径便捷分发:时间为分发时刻,file/line 为 Swift 调用点。
  static func emit(
    _ level: RimeLogLevel,
    _ message: String,
    file: String = #fileID,
    line: UInt = #line
  ) {
    let now = Date()
    emit(
      RimeLogRecord(
        level: level,
        message: message,
        file: file,
        fullFilename: nil,
        line: Int(line),
        unixTimeMillis: Int64((now.timeIntervalSince1970 * 1000).rounded()),
        utcOffsetSeconds: TimeZone.current.secondsFromGMT()))
  }
}

/// librime logsink 安装与配置:把 glog 记录转发到 `RimeLog` 注册的回调
/// 并可静音 stderr。模块构造器注册先于 setup,`install()` 在任意阶段可调用
/// (越早安装,能捕获的组件注册/部署日志越全);幂等(同一 context)。
///
/// 回调约束(头文件):在日志调用线程上运行、可能并发;不得回逆进入
/// librime 日志(同步 LOG 带锁重入死锁)、不得在回调内调
/// set_stderr_threshold;保持短小——回调内的处理与落盘耗时直接拖慢
/// 日志线程,非阻塞性由宿主回调自行保证。
public enum RimeLogSink {
  /// 安装转发 sink 并静音 stderr。幂等(add_sink 对同一 context 返回
  /// false 无副作用)。
  public static func install(rimeApi: RimeApi) {
    guard
      let logsink = rimeApi.find_module?("logsink")?
        .pointee.get_api()
        .map({ UnsafeMutableRawPointer($0).assumingMemoryBound(to: RimeLogSinkApi.self) })
    else {
      RimeLog.emit(.error, "logsink module unavailable; glog 维持文件/stderr 现状")
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
  RimeLog.emit(
    RimeLogRecord(
      level: RimeLogLevel(rawValue: Int32(r.severity.rawValue)) ?? .warning,
      message: message,
      file: r.base_filename.map { String(cString: $0) },
      fullFilename: r.full_filename.map { String(cString: $0) },
      line: Int(r.line),
      unixTimeMillis: r.unix_time_millis,
      utcOffsetSeconds: Int(r.utc_offset_seconds)))
}

/// librime ERROR 及以上记录的进程内收集器,经 `RimeLogSink.installErrorCollector()`
/// 安装。部署与配置 link 的多数失败只出现在 glog 记录里(返回值仍为成功),
/// 收集器是把这类失败变成可编程判据的通道。
///
/// 回调约束同转发 sink(在日志调用线程上运行、可能并发;不得回逆进入
/// librime 日志):内部只做加锁赋值。
public final class RimeLogErrorCollector: Sendable {
  private struct State: Sendable {
    var first: String?
    var installed = true
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// 首条 ERROR 及以上记录,格式 `[文件:行] 内容`;尚无记录时为 nil。
  public var firstError: String? {
    state.withLock { $0.first }
  }

  func record(_ message: String) {
    state.withLock {
      if $0.first == nil { $0.first = message }
    }
  }

  /// 摘除 sink。幂等;摘除后收集器停止更新。不摘除则随进程存活——与转发
  /// sink 的常驻语义一致。注:并发调用时返回的一方不构成"摘除已完成"屏障
  /// ——摘除动作在锁外完成(唯一调用方为部署工具的 defer,无并发面)。
  public func uninstall() {
    let shouldRemove = state.withLock { state -> Bool in
      guard state.installed else { return false }
      state.installed = false
      return true
    }
    guard shouldRemove else { return }
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
