// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// 部署领域测试,独立 target(macOS 限定内容 + iOS 占位用例,见文件尾)。
// 整个领域矩阵以 `Process` 依赖 macOS——部署工具是构建宿主的构件。
//
// target 结构约束(两条都是 CI 实证,勿合并/勿删):
// ① 本 target 在 iOS 上恒无领域用例,但 swift-testing 包**不可为空**——空包
//    在 Xcode 26 的 xctest 引导期即退出("Early unexpected exit"),且
//    -skip-testing 挡不住(引导先于枚举)。文件尾的占位 suite 为此而设。
// ② 领域矩阵依赖的 RimeDeployCore 必须按平台条件化:插件会把 RimeDeploy
//    的可执行对象拖进挂插件之测试包的链接,与领域矩阵无关;本 target 不挂
//    插件,条件化后 iOS 链接图零重量。
//
// 领域矩阵(退出测试):`#expect(processExitsWith:)` 重新唤起一个**全新子进程**
// 执行闭包——夹具在闭包内生成,`runRimeDeploy` 进程内直接调用(含 Rime 初始化)。
// librime 进程级单 deployer 的约束由进程隔离满足;断言是 typed 的,子进程内的
// #expect/Issue 会传回父进程报告。夹具路径、内容与全部状态都发生在子进程内部,
// 用例之间零共享——这是并行安全的依据。早期经进程级环境变量给闭包传可执行文件
// 路径与参数的实现正因并行互相覆盖而废弃;如今的修法是废除通道本身,而非换一条。
//
// 旧独立仓库时代另有 spawn 独立二进制的冒烟层,验证 artifactbundle 分发物的
// 进程合约;迁回本包后该层由 RimeDeployPluginTests 天然覆盖——插件构建命令
// 驱动的就是真实工具二进制,且经由消费方唯一会走的路径。

import Testing

#if os(macOS)
  import Foundation
  import RimeDeployCore

  /// 一份健康夹具编译出的全部产物(相对 out 目录,排序后)。
  private let probeArtifacts = [
    "probe.prism.bin", "probe.reverse.bin", "probe.schema.yaml", "probe.table.bin",
  ]

  /// 子进程内的夹具准备:全新目录 + 一份确实能编译的 schema 与词典,
  /// 于是每个用例只破坏一处。
  private func makeHealthyFixture() throws -> ToolFixture {
    let fixture = try ToolFixture.make()
    try fixture.writeHealthyData()
    return fixture
  }

  // MARK: - 领域矩阵

  @Suite("领域矩阵:退出测试——每用例全新子进程内进程内调用部署,断言 typed")
  struct RimeDeployExitTests {
    @Test func healthyDataCompiles() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }

        let outcome = try await runRimeDeploy(
          fixture.request(expected: [
            "probe.schema.yaml", "probe.table.bin", "probe.prism.bin", "probe.reverse.bin",
          ]))
        #expect(outcome.verifiedArtifacts == 4)
        #expect(outcome.removedStaleFiles == 0)
        #expect(fixture.files(in: fixture.out) == probeArtifacts)
      }
    }

    @Test("二轮构建:声明集即清留判据——未声明者清扫后由 librime 重建,仍最新的产物必须复用")
    func runningTwiceLeavesCurrentArtifacts() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }
        let request = fixture.request(expected: [
          "probe.schema.yaml", "probe.table.bin", "probe.prism.bin", "probe.reverse.bin",
        ])

        _ = try await runRimeDeploy(request)
        let table = fixture.out.appendingPathComponent("probe.table.bin")
        let before =
          try FileManager.default
          .attributesOfItem(atPath: table.path)[.modificationDate] as? Date

        _ = try await runRimeDeploy(request)

        let after =
          try FileManager.default
          .attributesOfItem(atPath: table.path)[.modificationDate] as? Date
        #expect(before == after, "工具不得强制重建;复用是编译器校验和的本分")
      }
    }

    // MARK: - 拒绝

    @Test func missingDataDirectoryFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try ToolFixture.make()
        defer { fixture.remove() }

        do {
          _ = try await runRimeDeploy(fixture.request(expected: ["probe.table.bin"]))
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("--data-dir does not exist"))
        }
      }
    }

    @Test func dataPathThatIsAFileFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try ToolFixture.make()
        defer { fixture.remove() }
        try fixture.write("not a directory", to: fixture.data)

        do {
          _ = try await runRimeDeploy(fixture.request())
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("--data-dir is not a directory"))
        }
      }
    }

    @Test("schema_id 缺失:librime 经返回值报错,无需日志收集器即可捕获")
    func schemaWithoutIDFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try ToolFixture.make()
        defer { fixture.remove() }
        try fixture.write(
          "not_a_schema: true\n",
          to: fixture.data.appendingPathComponent("broken.schema.yaml"))

        do {
          _ = try await runRimeDeploy(fixture.request(expected: ["broken.schema.yaml"]))
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("prebuild failed"))
        }
      }
    }

    @Test("无法解析的 __include:librime 以成功返回、什么都不写,只有日志收集器能把它变成失败")
    func unresolvableIncludeFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }
        try fixture.append(
          "\n__include: nowhere.yaml\n",
          to: fixture.data.appendingPathComponent("probe.schema.yaml"))

        do {
          _ = try await runRimeDeploy(fixture.request(expected: ["probe.schema.yaml"]))
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("unresolved dependency"))
        }
      }
    }

    @Test func declaredArtifactThatIsMissingFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }

        do {
          _ = try await runRimeDeploy(
            fixture.request(expected: ["probe.table.bin", "absent.bin"]))
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("absent.bin"))
        }
      }
    }

    // MARK: - 清除

    @Test("librime 不清除陈旧产物:未声明者随构建被清扫,被清空的目录一并移除")
    func artifactsOfRemovedDataAreSwept() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }
        let request = fixture.request(expected: [
          "probe.schema.yaml", "probe.table.bin", "probe.prism.bin", "probe.reverse.bin",
        ])
        _ = try await runRimeDeploy(request)

        try fixture.write(
          "stale", to: fixture.out.appendingPathComponent("removed.table.bin"))
        try fixture.write("stale", to: fixture.out.appendingPathComponent("opencc/old.json"))

        let outcome = try await runRimeDeploy(request)

        #expect(outcome.removedStaleFiles == 2)
        #expect(fixture.files(in: fixture.out) == probeArtifacts)
        #expect(
          !FileManager.default.fileExists(
            atPath: fixture.out.appendingPathComponent("opencc").path),
          "被清扫文件留下的目录也一并消失")
      }
    }

    @Test("零声明:无从区分产物与早于本次数据集的遗留物,清扫全面禁用")
    func declaringNothingSweepsNothing() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }

        let outcome = try await runRimeDeploy(fixture.request())

        #expect(outcome.verifiedArtifacts == 0)
        #expect(outcome.removedStaleFiles == 0)
        #expect(fixture.files(in: fixture.out) == probeArtifacts)
      }
    }

    // MARK: - 复制的数据

    @Test("also-copy 者同入声明集:复制由部署逻辑完成,清扫保留——插件才能声明整目录")
    func copiedDataIsKeptAndCopied() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }
        try fixture.write("t2s", to: fixture.data.appendingPathComponent("opencc/t2s.json"))

        let outcome = try await runRimeDeploy(
          fixture.request(expected: ["probe.table.bin"], alsoCopy: ["opencc/t2s.json"]))

        #expect(outcome.verifiedArtifacts == 1)
        let copied = fixture.out.appendingPathComponent("opencc/t2s.json")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "t2s")
      }
    }

    @Test("also-copy 重跑:同一输出目录二轮部署幂等成功(先删后拷)")
    func copiedDataSurvivesRerun() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }
        try fixture.write("t2s", to: fixture.data.appendingPathComponent("opencc/t2s.json"))
        let request = fixture.request(expected: ["probe.table.bin"], alsoCopy: ["opencc/t2s.json"])

        _ = try await runRimeDeploy(request)
        let outcome = try await runRimeDeploy(request)

        #expect(outcome.verifiedArtifacts == 1)
        let copied = fixture.out.appendingPathComponent("opencc/t2s.json")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "t2s")
      }
    }

    @Test func missingCopySourceFails() async {
      await #expect(processExitsWith: .success) {
        let fixture = try makeHealthyFixture()
        defer { fixture.remove() }

        do {
          _ = try await runRimeDeploy(
            fixture.request(expected: ["probe.table.bin"], alsoCopy: ["absent.yaml"]))
          Issue.record("expected the deployment to be rejected")
        } catch let error as RimeDeployError {
          #expect(error.description.contains("--also-copy absent.yaml"))
        }
      }
    }
  }

  /// 一次测试用完即弃的目录。
  struct ToolFixture {
    let root: URL
    var data: URL { root.appendingPathComponent("data") }
    var out: URL { root.appendingPathComponent("out") }
    var work: URL { root.appendingPathComponent("work") }

    static func make() throws -> ToolFixture {
      let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rime-deploy-e2e-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      return ToolFixture(root: root)
    }

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }

    func write(_ contents: String, to url: URL) throws {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 追加而非覆盖,好让测试只破坏一份本来健康的数据的某一部分。
    func append(_ contents: String, to url: URL) throws {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(contents.utf8))
    }

    /// 一份确实能编译的 schema 与词典,于是每个测试只破坏一处。
    func writeHealthyData() throws {
      try write(
        """
        schema:
          schema_id: probe
          name: Probe
          version: "1"
        translator:
          dictionary: probe
        """, to: data.appendingPathComponent("probe.schema.yaml"))
      try write(
        """
        ---
        name: probe
        version: "1"
        sort: original
        ...
        ni\t你
        """, to: data.appendingPathComponent("probe.dict.yaml"))
    }

    func files(in directory: URL) -> [String] {
      relativeFilePaths(in: directory.path).sorted()
    }

    /// 针对这些目录的部署请求(退出测试进程内直接调用)。
    func request(
      expected: [String] = [],
      alsoCopy: [String] = [],
      mode: RimeDeployMode = .prebuild
    ) -> RimeDeployRequest {
      RimeDeployRequest(
        dataDirectory: data.path,
        outputDirectory: out.path,
        workDirectory: work.path,
        mode: mode,
        expected: expected,
        alsoCopy: alsoCopy)
    }
  }

  /// `directory` 下任意深度的全部文件,以相对路径表示。
  ///
  /// 与被测工具用的是同一套定义,在这里独立实现,以免测试依赖被测代码来判定
  /// 自己的观察结果。
  private func relativeFilePaths(in directory: String) -> [String] {
    guard let walker = FileManager.default.enumerator(atPath: directory) else { return [] }
    var relative: [String] = []
    while let entry = walker.nextObject() as? String {
      var isDirectory: ObjCBool = false
      let path = "\(directory)/\(entry)"
      guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else { continue }
      relative.append(entry)
    }
    return relative
  }

#else

  /// iOS 等平台上部署工具不存在(构建宿主构件),领域矩阵整体不编译;本 suite
  /// 只为让 swift-testing 包不为空——空包会让 Xcode 26 的 xctest 在引导期退出
  /// (见文件头 target 结构约束①)。
  @Suite("部署工具:iOS 上无此构件")
  struct RimeDeployToolPlaceholderTests {
    @Test("领域矩阵 os(macOS) 限定;本用例只为保 swift-testing 包非空")
    func placeholderKeepsBundleNonEmpty() {
      #expect(true, "iOS 上无部署工具可断言;空包会在 xctest 引导期崩(见文件头)")
    }
  }

#endif
