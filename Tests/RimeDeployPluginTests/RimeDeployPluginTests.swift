// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import RimeKit
import Testing

// 本 target 把本包的插件应用到自己数据目录的数据上,因此构建测试就是以消费方
// 的方式驱动插件:插件运行、RimeDeploy 编译数据、结果作为 target 的资源交回。
// 数据目录有两个——惯例名 `RimeData` 与非常规名 `MyRimeData` 并存,正好断言
// 一般情况:插件按内容(`*.schema.yaml`)而非名字定位,每个数据集各编译一份,
// 编译目录沿用输入目录名,在 bundle 里并列不撞车。
//
// 插件在这里测而不是并入工具自己的 suite,是因为这些断言针对"插件声明了什么、
// 构建系统如何把它带进 bundle"——比工具高一层。
//
// 本 target 覆盖不了工具对坏数据的拒绝:构建命令失败会中断构建,内部无从断言。
// 那是 RimeDeployToolTests 的事。
@Suite("插件层:构建期编译如何进 bundle——目录结构、目录名、可加载性")
struct RimeDeployPluginTests {
  /// 插件为本 target 准备的编译数据目录。
  ///
  /// `Bundle.module` 就是本 target 的资源 bundle——本 target 有资源(其中包含
  /// 声明为输出的那些目录),SwiftPM 因此生成了访问器。这里不需要知道 bundle
  /// 的名字,也不必猜测测试 bundle 把它嵌在哪一层。
  private func compiledData(named name: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent(name)
  }

  private func contents(of directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.sorted() ?? []
  }

  @Test func compiledArtifactsReachTheBundle() {
    let directory = compiledData(named: "RimeData")
    #expect(
      FileManager.default.fileExists(atPath: directory.path),
      "the plugin produced no RimeData directory; found \(contents(of: directory.deletingLastPathComponent()))"
    )

    let files = contents(of: directory)
    // schema 与词典各自应产出的产物。
    #expect(files.contains("probe.schema.yaml"))
    #expect(files.contains("probe.table.bin"))
    #expect(files.contains("probe.prism.bin"))
    #expect(files.contains("probe.reverse.bin"))
  }

  @Test("所有直接含 *.schema.yaml 的目录都被编译:名字不特殊,编译目录沿用目录名")
  func everyDataDirectoryIsCompiled() {
    // 惯例名与非常规名并存于同一 target:两者都是按内容找到的普通数据集,
    // 各编译一份,在 bundle 根并列——目录名互异,故互不撞车。
    for name in ["RimeData", "MyRimeData"] {
      let directory = compiledData(named: name)
      #expect(
        FileManager.default.fileExists(atPath: directory.path),
        "\(name) 未编译进 bundle:found \(contents(of: directory.deletingLastPathComponent()))"
      )
      let files = contents(of: directory)
      #expect(files.contains("probe.table.bin"), "\(name): \(files)")
      #expect(files.contains("probe.prism.bin"), "\(name): \(files)")
    }
  }

  @Test("import_tables 布局:被导入表合并进主表,不单独产出产物")
  func importedTablesMergeIntoMain() {
    // WanxiangData 的主表 import 子表(dicts/zi):librime 把被导入表合并进
    // 主表三件套——被导入表不产出任何 bin,插件也不得为它们声明预期。
    let directory = compiledData(named: "WanxiangData")
    #expect(
      FileManager.default.fileExists(atPath: directory.path),
      "插件未为 import_tables 布局产出数据目录:found \(contents(of: directory.deletingLastPathComponent()))"
    )

    let files = contents(of: directory)
    #expect(files.contains("wanxiang.schema.yaml"), "found \(files)")
    #expect(files.contains("wanxiang.table.bin"), "found \(files)")
    #expect(files.contains("wanxiang.prism.bin"), "found \(files)")
    #expect(
      !files.contains(where: { $0.hasPrefix("zi.") || $0.hasPrefix("dicts/") }),
      "被导入表不得单独产出:found \(files)"
    )
  }

  @Test("外来词典:prism 名跟输入词典走,除非 translator/prism 显式点名;孤儿词典零产出")
  func foreignDictionaryPrismNamingAndOrphan() {
    // 万象布局的第二处坑:wanxiang_phrase schema 的输入表是 custom_phrase——
    // 未点名 prism 时产出的 prism 与词典同名(custom_phrase.prism.bin),不
    // 是 schema_id;wanxiang_phrase_t9 显式点名了自己的 prism。dicts/t9_abbrev
    // 无人引用,连二库都没有。按"每本词典三件套"或按 schema_id 推断 prism,
    // 这两类都会被核对误杀。
    let files = contents(of: compiledData(named: "WanxiangData"))
    #expect(files.contains("custom_phrase.table.bin"), "found \(files)")
    #expect(files.contains("custom_phrase.reverse.bin"), "found \(files)")
    #expect(files.contains("custom_phrase.prism.bin"), "found \(files)")
    #expect(!files.contains("wanxiang_phrase.prism.bin"), "found \(files)")
    #expect(files.contains("wanxiang_phrase_t9.prism.bin"), "found \(files)")
    #expect(
      !files.contains(where: { $0.hasPrefix("t9_abbrev.") }), "found \(files)")
  }

  @Test func nestedDataKeepsItsLayout() {
    // 编译数据以单个目录声明,因此保留数据目录的布局——包括 librime 按名字
    // 解析的路径,如 `<shared>/opencc/<name>`。若逐个声明输出文件,它们会被
    // 摊平到资源根,结构就丢了。
    let opencc = compiledData(named: "RimeData").appendingPathComponent("opencc")
    #expect(
      FileManager.default.fileExists(atPath: opencc.path),
      "nested directory did not survive: \(contents(of: compiledData(named: "RimeData")))")
    #expect(contents(of: opencc) == ["t2s.json"])
  }

  // 退出测试 API 在 iOS 上不可用,而引擎使用又必须隔离在子进程里——本用例
  // 以 macOS 为限(iOS 上编译剔除,零用例运行);bundle 的其余断言平台中性。
  #if os(macOS)
    @Test("进程内能拿到的最强检查:编译产物可被 RimeKit 直接加载(select_schema 成功)")
    func compiledDataIsLoadable() async {
      // 引擎初始化发生在退出测试的全新子进程内:统一 runner 形态下多个 bundle
      // 共享一个进程,进程内的引擎状态会跨 bundle 污染(实证:引导部署失败),
      // 子进程隔离让本用例在任何 runner 形态下都零残留。
      await #expect(processExitsWith: .success) {
        let userDirectory = NSTemporaryDirectory() + "rime-plugin-tests-\(getpid())"
        try? FileManager.default.createDirectory(
          atPath: userDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: userDirectory) }

        let traits = RimeTraits(
          sharedDataDir: userDirectory,
          userDataDir: userDirectory,
          distributionName: "tests",
          distributionCodeName: "tests",
          distributionVersion: "1",
          appName: "rime.tests",
          minLogLevel: .fatal,
          logDir: "",
          prebuiltDataDir: Bundle.module.resourceURL!.appendingPathComponent("RimeData").path,
          stagingDir: userDirectory)

        // 子进程独占引擎,进程退出即回收,不做 finalize。
        let root = Rime.localShared
        try await root.setup(with: traits)
        try await root.initialize(with: traits)

        let session = try #require(await root.createSession())
        #expect(try await root.selectSchema("probe", for: session) == true)
      }
    }
  #endif
}
