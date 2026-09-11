// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import RimeKit

/// 目录布局:配置/部署分离 + 部署代次隔离(§4.3 蓝绿磁盘模型)。
/// 纯路径演算与文件系统布局,不触引擎。
@Suite struct RimeDirectoryLayoutTests {
  private let root = URL(filePath: "/tmp/rimekit-layout-sample")

  @Test func generationsIsolateDeploymentButShareConfiguration() {
    let blue = RimeDirectoryLayout(root: root, generation: .blue)
    let green = RimeDirectoryLayout(root: root, generation: .green)

    // 配置目录共享:蓝绿切换零迁移零丢失。
    #expect(blue.configurationDirectory == green.configurationDirectory)
    // 部署与日志按代隔离:绿机重部署不掀蓝机的桌。
    #expect(blue.stagingDirectory != green.stagingDirectory)
    #expect(blue.logDirectory != green.logDirectory)
    #expect(blue.stagingDirectory.path.contains("deploy/blue"))
    #expect(green.stagingDirectory.path.contains("deploy/green"))
  }

  @Test func layoutLivesOutsideConfigurationDirectory() {
    // 配置与部署分离:部署/日志不得落在配置目录之内(用户目录只含可编辑文件)。
    let layout = RimeDirectoryLayout(root: root, generation: .blue)
    #expect(layout.stagingDirectory.path.hasPrefix(layout.configurationDirectory.path) == false)
    #expect(layout.logDirectory.path.hasPrefix(layout.configurationDirectory.path) == false)
  }

  @Test func makeTraitsWiresDirectories() {
    let layout = RimeDirectoryLayout(root: root, generation: .green)
    let traits = layout.makeTraits(
      sharedDataDir: root.appending(path: "share"),
      distributionName: "RimeKit",
      distributionCodeName: "dev.rimekit",
      distributionVersion: "0.1",
      appName: "Test")

    #expect(traits.sharedDataDir == root.appending(path: "share").path)
    #expect(traits.userDataDir == layout.configurationDirectory.path)
    #expect(traits.stagingDir == layout.stagingDirectory.path)
    #expect(traits.logDir == layout.logDirectory.path)
  }

  @Test func prepareCreatesDirectoriesIdempotently() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "rimekit-layout-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let layout = RimeDirectoryLayout(root: root, generation: .blue)
    try layout.prepare()
    try layout.prepare()  // 幂等

    for directory in [layout.configurationDirectory, layout.stagingDirectory, layout.logDirectory] {
      var isDirectory: ObjCBool = false
      #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
      #expect(isDirectory.boolValue)
    }
  }
}
