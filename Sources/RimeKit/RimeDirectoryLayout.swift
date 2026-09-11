// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 服务代次:蓝绿双实例的磁盘槽位标识(§4.1)。
public enum RimeServiceGeneration: String, Sendable {
  case blue
  case green
}

/// 磁盘目录布局:**配置与部署分离 + 部署按代次隔离**(§4.3)。
///
/// ```text
/// root/
/// ├── config/          ← 配置目录(userDataDir):用户 yaml、user.yaml、用户词典
/// │                      跨代次共享且稳定——蓝绿切换零迁移、零丢失
/// ├── deploy/blue/     ← 部署目录(stagingDir):blue 代编译产物(隔离)
/// ├── deploy/green/    ← 部署目录(stagingDir):green 代编译产物(隔离)
/// └── log/<gen>/       ← 日志:按代隔离,便于对照排障
/// ```
///
/// 冲突模型(§4.3 蓝绿不变式):绿机预热只做部署(写 `deploy/green`),
/// 蓝机在役只读自己的 `deploy/blue` 并持有用户词典——**不会双机同时在役**,
/// 故共享配置目录(含 leveldb 单写者)安全;部署产物代次隔离后,绿机重部署
/// 不会掀蓝机的桌。
///
/// 配置目录与部署目录分离的直接收益:编译产物(易失、可再生)不再混入用户
/// 可编辑目录,备份/同步/审查用户配置时天然干净。
public struct RimeDirectoryLayout: Sendable {
  /// 布局根目录(宿主决定:如 `~/Library/Application Support/<App>/rime`
  /// 或 iOS App Group 容器)。
  public let root: URL
  /// 本布局所属代次。
  public let generation: RimeServiceGeneration

  public init(root: URL, generation: RimeServiceGeneration) {
    self.root = root
    self.generation = generation
  }

  /// 配置目录(= librime `userDataDir`)。
  public var configurationDirectory: URL {
    root.appending(path: "config", directoryHint: .isDirectory)
  }

  /// 部署目录(= librime `stagingDir`):本代编译产物,按代隔离。
  public var stagingDirectory: URL {
    root
      .appending(path: "deploy", directoryHint: .isDirectory)
      .appending(path: generation.rawValue, directoryHint: .isDirectory)
  }

  /// 日志目录:按代隔离。
  public var logDirectory: URL {
    root
      .appending(path: "log", directoryHint: .isDirectory)
      .appending(path: generation.rawValue, directoryHint: .isDirectory)
  }

  /// 创建布局目录(宿主在预热/初始化前调用;幂等)。
  public func prepare() throws {
    for directory in [configurationDirectory, stagingDirectory, logDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  /// 由布局构造 traits:`userDataDir` = 配置目录、`stagingDir` = 部署目录、
  /// `logDir` = 日志目录;`sharedDataDir` 与分发信息由宿主给定。
  public func makeTraits(
    sharedDataDir: URL,
    distributionName: String,
    distributionCodeName: String,
    distributionVersion: String,
    appName: String
  ) -> RimeTraits {
    var traits = RimeTraits(
      sharedDataDir: sharedDataDir.path,
      userDataDir: configurationDirectory.path,
      distributionName: distributionName,
      distributionCodeName: distributionCodeName,
      distributionVersion: distributionVersion,
      appName: appName
    )
    traits.stagingDir = stagingDirectory.path
    traits.logDir = logDirectory.path
    return traits
  }
}
