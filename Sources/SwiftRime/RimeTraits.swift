import CLibrime

/// The configuration for initializing RimeEngine.
public struct RimeTraits: Sendable, Codable {
	var sharedDataDir: String
	var userDataDir: String
	var distributionName: String
	var distributionCodeName: String
	var distributionVersion: String
	var appName: String
	var modules: [String] = []
	var minLogLevel: RimeLogLevel = .info
	var logDir: String? = nil
	var prebuiltDataDir: String? = nil
	var stagingDir: String? = nil
}

struct RimeTraitsReleaseHandle: ~Copyable {
	fileprivate var cStrings: [UnsafePointer<CChar>]
	fileprivate var cStringArrays: [UnsafeMutablePointer<UnsafePointer<CChar>?>?]

	deinit {
		for cString in cStrings {
			cString.deallocate()
		}
		for cStringArray in cStringArrays {
			cStringArray?.deallocateCStringArray()
		}
	}

	fileprivate mutating func add(_ string: String?) -> UnsafePointer<CChar> {
		guard let string else { return UnsafePointer(bitPattern: 0)! }
		let pointer = string.toCString()
		cStrings.append(pointer)
		return pointer
	}

	fileprivate mutating func add(_ stringArray: [String]) -> UnsafeMutablePointer<
		UnsafePointer<CChar>?
	> {
		let pointer = stringArray.toNullTerminatedCStringArray()
		cStringArrays.append(pointer)
		return pointer
	}
}

extension RimeTraits {
	internal func toCStructure(_ c: inout rime_traits_t) -> RimeTraitsReleaseHandle {
		var handle = RimeTraitsReleaseHandle(cStrings: [], cStringArrays: [])
		c.shared_data_dir = handle.add(sharedDataDir)
		c.user_data_dir = handle.add(userDataDir)
		c.distribution_name = handle.add(distributionName)
		c.distribution_code_name = handle.add(distributionCodeName)
		c.distribution_version = handle.add(distributionVersion)
		c.app_name = handle.add(appName)
		c.modules = handle.add(modules)
		c.min_log_level = minLogLevel.rawValue
		c.log_dir = handle.add(logDir)
		c.prebuilt_data_dir = handle.add(prebuiltDataDir)
		c.staging_dir = handle.add(stagingDir)
		return handle
	}

}

public enum RimeLogLevel: Int32, Sendable, Codable {
	case info = 0
	case warning = 1
	case error = 2
	case fatal = 3
}
