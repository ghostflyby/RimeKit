import Foundation
import os
import RimeC

/// librime glog 转接目标。默认 librime 专属 subsystem(跨蓝绿代次稳定);
/// 宿主可在 librime 初始化前替换为自身 subsystem 并入统一检索。
public enum RimeLog {
	public nonisolated(unsafe) static var logger = Logger(
		subsystem: "dev.ghostflyby.rime", category: "librime")
}

extension Rime {

	/// librime logsink 插件接管:stderr 静音(SILENT)+ glog 记录全量转发
	/// os_log。须在 rimeApi.setup() 之后调用——log_dir = "" 禁用文件日志
	/// 的副作用会把 stderr 阈值抬到 INFO,更早设置会被覆盖。
	///
	/// 隐私:glog INFO+ 为引擎内部诊断(部署/字典/Lua),按宿主约定以
	/// public 落统一日志;键入内容仅存在于更低 VERBOSE 档,不进本通道。
	func installLogSink() {
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

}

/// C 回调:无捕获(可作 C 函数指针);context 为注册标识(恒 nil),此处
/// 无需状态。glog 约束:回调在日志调用线程上运行、可能并发;不得回逆进
/// 入 librime 日志;保持短小——os.Logger 满足全部约束。
private func rimeLogSinkCallback(
	_ context: UnsafeMutableRawPointer?, _ record: UnsafePointer<rime_logsink_record>?
) {
	guard let record else { return }
	let r = record.pointee

	let message: String
	if let ptr = r.message {
		let data = Data(bytes: ptr, count: r.message_length)
		message = String(data: data, encoding: .utf8)
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
