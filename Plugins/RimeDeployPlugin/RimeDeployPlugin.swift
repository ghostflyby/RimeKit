// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PackagePlugin

/// 在构建期编译 target 内附带的 Rime 数据,并把结果作为资源交给该 target,
/// 于是应用永远不需要在首次启动时部署。
///
/// 消费方清单中的用法:
///
/// ```swift
/// .executableTarget(
///   name: "App",
///   dependencies: [.product(name: "RimeKit", package: "RimeKit")],
///   exclude: ["RimeData"],
///   plugins: [.plugin(name: "RimeDeployPlugin", package: "RimeKit")]
/// )
/// ```
///
/// 数据目录里放的就是本应安装进 shared data 的 Rime 源(`*.schema.yaml`、
/// `*.dict.yaml`,以及它们引用的一切,含 `opencc/` 这类子目录)。编译结果以
/// **单个目录**资源交回 target,因此整套目录结构都保留到 bundle 里,每个编译
/// 目录都是一个自足的 prebuilt 目录,应用把 `prebuilt_data_dir` 指向它即可。
///
/// 数据目录靠查找 `*.schema.yaml` 定位,而不是靠名字:target 内**每个**直接
/// 含有 `*.schema.yaml` 的目录都是一个数据集,各编译一份、各以其目录名进
/// bundle(目录名互异,故互不撞车)。零个说明插件挂在了不带 Rime 数据的
/// target 上(共用一份清单的正当用法,不产生任何构建命令)。
@main
struct RimeDeployPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext, target: Target
  ) async throws -> [Command] {
    let tool = try context.tool(named: "RimeDeploy")

    // 每个数据集一条构建命令;零个数据集则零条命令。
    return try findDataDirectories(in: target).map { name in
      try buildCommand(tool: tool, context: context, target: target, name: name)
    }
  }

  /// 为一个数据目录生成构建命令。
  private func buildCommand(
    tool: PluginContext.Tool, context: PluginContext, target: Target, name: String
  ) throws -> Command {
    let dataDirectory = target.directoryURL.appending(path: name)

    // 任意深度的每个文件都是输入:增删改其一都会重跑工具,而输入路径集合的
    // 变化还会让 SwiftPM 重新规划这条命令。
    let relativeInputs = try relativeFiles(in: dataDirectory)
    let inputFiles = relativeInputs.map { dataDirectory.appending(path: $0) }

    // 声明**一个目录**而不是逐个产物。SwiftPM 会把声明为输出的目录连同结构
    // 拷进 bundle,而逐个文件会被摊平到资源根——librime 按路径解析嵌套资源
    // (`opencc/<name>`),摊平会静默破坏它。
    //
    // 输出目录沿用数据目录的名字,于是数据在 target 内的前缀就是它在 bundle 里
    // 的前缀;同名目录在同一个 target 里不存在,输出互不撞车。
    let outputDirectory = context.pluginWorkDirectoryURL.appending(path: name)

    // librime 将要产出的名字,由 schema 文件的内容推导(构建命令必须在运行
    // 前声明输出,而名字编码在数据内部,读 yaml 是唯一途径;数据内部的标识符
    // 与文件名一致——不一致时 RimeDeploy 会报出来):
    //
    // * 每个 *.schema.yaml 部署出同名编译配置,外加一个 prism——实证 librime
    //   以**输入词典的名字**为 prism 命名,而非 schema_id;translator/prism
    //   显式点名时用点名者(万象:wanxiang_phrase[_t9] 以 custom_phrase 为
    //   输入表又各自点名了自己的 prism,于是名为 custom_phrase 的 prism 不
    //   存在,按 schema_id 或按"每词典一个"声明都会误报);
    // * translator/dictionary 点名的词典编译出 table/reverse 二库;被
    //   import_tables 合并进主表的与无人引用的孤儿词典什么 bin 都不产出
    //   (万象的 dicts/ 子表、t9_abbrev);
    // * reverse_lookup/dictionary 指向的反查词典只为它声明 reverse 一库——
    //   它是被查询方,不作为输入表挂载。
    //
    // 词典源文件本身只活在编译期,既不声明也不复制。
    var expected = Set<String>()
    var copied: [String] = []
    var dictionaries = Set<String>()
    var reverseOnly = Set<String>()
    for relative in relativeInputs {
      if relative.hasSuffix(".schema.yaml") {
        let text = try String(
          contentsOf: dataDirectory.appending(path: relative), encoding: .utf8)
        let keys = deployKeys(in: text)
        expected.insert(relative)
        if let dictionary = keys.translatorDictionary {
          expected.insert("\((keys.translatorPrism ?? dictionary)).prism.bin")
          dictionaries.insert(dictionary)
        }
        if let reverse = keys.reverseLookupDictionary {
          reverseOnly.insert(reverse)
        }
      } else if relative.hasSuffix(".dict.yaml") {
        // 词典产出什么取决于有没有 schema 点名它(见上),不在源层面声明。
      } else {
        // 其余是 librime 在**运行期**读取而非编译的数据——`default.yaml` 决定
        // 默认选项与 schema 列表,`symbols.yaml` 在编译时被 punctuator 内联,
        // `opencc/` 在运行期按路径查找——因此原样复制。复制这一步让声明完整:
        // 工具会清除输出目录里它没被告知要产出的东西,而对被复制的文件而言,
        // 工具正是产出者。
        copied.append(relative)
      }
    }
    for dictionary in dictionaries {
      expected.insert("\(dictionary).table.bin")
      expected.insert("\(dictionary).reverse.bin")
      reverseOnly.remove(dictionary)
    }
    for dictionary in reverseOnly {
      expected.insert("\(dictionary).reverse.bin")
    }

    let arguments =
      [
        "--data-dir", dataDirectory.path(percentEncoded: false),
        "--out-dir", outputDirectory.path(percentEncoded: false),
        // work 目录按数据集隔离:各命令可被构建系统并行执行,是互不相干的
        // 进程(deploymentGate 只保护单进程内),librime 会往 user 目录写
        // installation.yaml 等状态,共享 work 目录就会互相覆盖。
        "--work-dir",
        context.pluginWorkDirectoryURL.appending(path: "work", directoryHint: .isDirectory)
          .appending(path: name)
          .path(percentEncoded: false),
        "--mode", "prebuild",
      ]
      + expected.sorted().flatMap { ["--expect", $0] }
      + copied.flatMap { ["--also-copy", $0] }

    return .buildCommand(
      displayName: "Compiling Rime data \(name) in \(target.name)",
      executable: tool.url,
      arguments: arguments,
      // 工具的链接形态随消费方 traits,由构建系统自带 rpath 解析,无需环境变量。
      inputFiles: inputFiles,
      outputFiles: [outputDirectory]
    )
  }

  /// schema.yaml 文本里与部署相关的顶层小节:`translator` 的 `dictionary`/
  /// `prism` 与 `reverse_lookup` 的 `dictionary`。只认惯例写法:顶格键行开
  /// 小节,缩进行收字段,行尾注释与成对引号剔除——雾凇/万象/官方方案皆同型;
  /// 同名字段出现在别处的不看(万象顶层 `custom_phrase.prism` 是运行期翻译器
  /// 的实例配置,不是部署产出物的名字来源)。
  private func deployKeys(in text: String) -> (
    translatorDictionary: String?, translatorPrism: String?, reverseLookupDictionary: String?
  ) {
    func value(_ line: Substring) -> String? {
      let parts = line.split(separator: ":", maxSplits: 1)
      guard parts.count == 2 else { return nil }
      let text = String(parts[1].split(separator: "#")[0]).trimmingCharacters(in: .whitespaces)
      let unquoted = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return unquoted.isEmpty ? nil : unquoted
    }

    var translatorDictionary: String?
    var translatorPrism: String?
    var reverseLookupDictionary: String?
    var section: Substring?
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
        guard let section else { continue }
        let line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
        if line.hasPrefix("dictionary:") {
          switch section {
          case "translator": translatorDictionary = value(line)
          case "reverse_lookup": reverseLookupDictionary = value(line)
          default: break
          }
        } else if section == "translator", line.hasPrefix("prism:") {
          translatorPrism = value(line)
        }
      } else {
        let line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
        if line == "..." { break }
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        section = line.firstIndex(of: ":").map { line[..<$0] }
      }
    }
    return (translatorDictionary, translatorPrism, reverseLookupDictionary)
  }

  /// target 内的全部数据目录:每个**直接**躺着 `*.schema.yaml` 的目录都是一个
  /// 数据根——这正是它区别于数据根子目录的标志。按内容定位,名字只是前缀。
  private func findDataDirectories(in target: Target) throws -> [String] {
    let targetDirectory = target.directoryURL
    let entries = try FileManager.default
      .contentsOfDirectory(atPath: targetDirectory.path(percentEncoded: false))
      .filter { !$0.hasPrefix(".") }

    var directories: [String] = []
    for entry in entries {
      let path = targetDirectory.appending(path: entry)
      var isDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(
          atPath: path.path(percentEncoded: false), isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      let contents =
        (try? FileManager.default.contentsOfDirectory(
          atPath: path.path(percentEncoded: false))) ?? []
      if contents.contains(where: { $0.hasSuffix(".schema.yaml") }) {
        directories.append(entry)
      }
    }
    return directories.sorted()
  }

  /// `directory` 下任意深度的每个文件,以相对路径表示。
  private func relativeFiles(in directory: URL) throws -> [String] {
    let root = directory.path(percentEncoded: false)
    guard let walker = FileManager.default.enumerator(atPath: root) else {
      return []
    }
    var files: [String] = []
    while let entry = walker.nextObject() as? String {
      // 跳过点文件与点目录,免得 .DS_Store 之类混进输入集合。
      guard !entry.hasPrefix("."),
        !entry.split(separator: "/").contains(where: { $0.hasPrefix(".") })
      else { continue }
      var isDirectory: ObjCBool = false
      let path = directory.appending(path: entry).path(percentEncoded: false)
      guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else { continue }
      files.append(entry)
    }
    return files.sorted()
  }
}
