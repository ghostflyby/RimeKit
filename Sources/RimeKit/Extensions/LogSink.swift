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

/// 分级回调槽:转发与散点错误共用的分发目标,由 `RimeLogSink.install(handler:)`
/// 注册;未注册时记录丢弃。
enum RimeLog {
  private static let storage = OSAllocatedUnfairLock<RimeLogHandler?>(initialState: nil)

  /// 注册回调(nil 摘除);重复注册以后一次为准。
  static func set(handler: RimeLogHandler?) {
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

/// librime logsink 端点:该插件全部日志操作的入口,经 `Rime.plugin.logSink()`
/// 获取(模块缺失时为 nil——不支持可明确感知)。
///
/// 回调约束(头文件):在日志调用线程上运行、可能并发;不得回逆进入
/// librime 日志(同步 LOG 带锁重入死锁)、不得在回调内调
/// set_stderr_threshold;保持短小——回调内的处理与落盘耗时直接拖慢
/// 日志线程,非阻塞性由宿主回调自行保证。
public struct RimeLogSink {
  let api: UnsafeMutablePointer<RimeLogSinkApi>

  /// 注册分级回调并安装转发、静音 stderr,一步完成;越早调用,能捕获的
  /// 组件注册/部署日志越全。返回 false=已安装(add_sink 对同一 context
  /// 重复注册返回 false);handler 无论返回值均已生效,后续记录走新回调。
  @discardableResult
  public func install(handler: RimeLogHandler?) -> Bool {
    RimeLog.set(handler: handler)
    api.pointee.set_stderr_threshold(.silent)
    return api.pointee.add_sink(nil, rimeLogSinkCallback)
  }
}

extension RimePlugin {
  /// logsink 端点;模块缺失(编译时未编入)返回 nil——不支持可明确感知。
  /// 模块构造器注册先于 setup,任意阶段可获取。
  public func logSink() -> RimeLogSink? {
    rime_get_api()?.pointee.find_module?("logsink")?.pointee.get_api()
      .map { raw in
        RimeLogSink(
          api: UnsafeMutableRawPointer(raw)
            .assumingMemoryBound(to: RimeLogSinkApi.self))
      }
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
