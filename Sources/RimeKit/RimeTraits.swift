// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import RimeDynamic

/// The configuration for initializing RimeEngine.
public struct RimeTraits: Sendable, Codable {
  public var sharedDataDir: String
  public var userDataDir: String
  public var distributionName: String
  public var distributionCodeName: String
  public var distributionVersion: String
  public var appName: String
  public var modules: [String] = []
  public var minLogLevel: RimeLogLevel = .info
  public var logDir: String? = nil
  public var prebuiltDataDir: String? = nil
  public var stagingDir: String? = nil

  public init(
    sharedDataDir: String,
    userDataDir: String,
    distributionName: String,
    distributionCodeName: String,
    distributionVersion: String,
    appName: String,
    modules: [String] = [],
    minLogLevel: RimeLogLevel = .info,
    logDir: String? = nil,
    prebuiltDataDir: String? = nil,
    stagingDir: String? = nil
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

  fileprivate mutating func add(_ string: String?) -> UnsafePointer<CChar>? {
    guard let string else { return nil }
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
    // 空模块表必须写 NULL:librime 以 NULL 表示"加载全部内建模块"(Squirrel 缺省
    // 即此形态);非 NULL 的零项数组则一个模块都不加载,引擎因缺组件而瘫痪。
    c.modules = modules.isEmpty ? nil : handle.add(modules)
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
