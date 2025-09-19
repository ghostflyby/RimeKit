import CLibrime

public class RimeTraits  {
	@CString internal var sharedDataDir: String
	@CString internal var userDataDir: String
	@CString internal var distributionName: String
	@CString internal var distributionCodeName: String
	@CString internal var distributionVersion: String
	@CString internal var appName: String
	@CStringArray internal var modules: [String]
	internal let minLogLevel: RimeLogLevel
	@CString internal var logDir: String
	@CString internal var prebuiltDataDir: String
	@CString internal var stagingDir: String

	public init(
		sharedDataDir: String,
		userDataDir: String,
		distributionName: String,
		distributionCodeName: String,
		distributionVersion: String,
		appName: String,
		modules: [String] = [],
        minLogLevel: RimeLogLevel = .info,
		logDir: String = "",
		prebuiltDataDir: String = "",
		stagingDir: String = ""
	) {
		self.sharedDataDir = sharedDataDir
		self.userDataDir = userDataDir
		self.distributionName = distributionName
		self.distributionCodeName = distributionCodeName
		self.distributionVersion = distributionVersion
		self.appName = appName
		self.modules = modules
		self.minLogLevel = minLogLevel
		self.logDir = logDir
		self.prebuiltDataDir = prebuiltDataDir
		self.stagingDir = stagingDir
	}
    
}

extension RimeTraits : SwiftDataSized {
    internal typealias CType = rime_traits_t
    internal func toCStructure(with c: inout rime_traits_t) {
        c.shared_data_dir = $sharedDataDir
        c.user_data_dir = $userDataDir
        c.distribution_name = $distributionName
        c.distribution_code_name = $distributionCodeName
        c.distribution_version = $distributionVersion
        c.app_name = $appName
        c.modules = $modules
        c.min_log_level = minLogLevel.rawValue
        c.log_dir = $logDir
        c.prebuilt_data_dir = $prebuiltDataDir
        c.staging_dir = $stagingDir
    }

}

public enum RimeLogLevel: Int32 {
    case info = 0
    case warning = 1
    case error = 2
    case fatal = 3
}
    
