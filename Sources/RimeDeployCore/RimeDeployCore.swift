// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import RimeKit
import SystemPackage
import os

/// 构建期 Rime 部署工具:把 YAML 源编译成客户端运行期加载的二进制产物——
/// 编译后的 schema 配置,以及每本词典的 table/prism/reverse 数据库。
///
/// 它是上游 `rime_deployer` 的 Swift 对应物,引擎操作全部走 RimeKit 的进程内
/// 共享根(`Rime.localShared`)——与运行期消费方同一套 Swift API,这条工具链
/// 本身就是该 API 的生产验证。
///
/// 逻辑放在库里而不是直接写在可执行文件里,是为了让测试能在进程内调用失败路径:
/// 构建命令非零退出会中断构建,应用插件的 target 无法对失败做断言。可执行文件
/// 只是这层的参数解析外壳。

public let rimeDeployToolName = "rime-deploy"

public enum RimeDeployMode: String, Sendable {
  /// 编译数据目录里每一个 `*.schema.yaml`;不产出 workspace 配置,
  /// 因此除数据本身之外不需要别的东西。
  case prebuild
  /// 另外编译 `default.yaml`,这要求其中有 `schema_list`。
  case deploy
}

/// 路径字段一律 `FilePath`(System):库内的路径表示与计算走这一类别;
/// 文件系统 I/O 由实现内部转换为 URL,见 helpers 区的类别说明。
public struct RimeDeployRequest: Sendable {
  /// 源数据:`*.schema.yaml`、`*.dict.yaml` 及其引用的一切。作为 librime 的
  /// `shared_data_dir` 传入,绝不写入。
  public var dataDirectory: FilePath
  /// 数据集根目录:also-copy 的源数据落在根,编译产物落在其 `build/` 子目录
  /// ——标准 rime 目录形态。作为 librime 的 `staging_dir` 的是 `build/`。
  public var outputDirectory: FilePath
  /// 可写草稿目录,作为 `user_data_dir` 传入;默认 `<outputDirectory>-work`。
  public var workDirectory: FilePath?
  public var mode: RimeDeployMode
  /// 调用方期望的产物,相对**staging 根**(`outputDirectory/build`)。它们会被
  /// 断言存在,同时共同定义了"输出目录里哪些文件属于本次数据"——其余一律清除。
  public var expected: [FilePath]
  /// 原样复制而非编译的数据,相对 `dataDirectory`,落在数据集**根**(与
  /// `build/` 里的编译产物并列)。用于 librime 在**运行期**按路径读取的
  /// 东西:`default.yaml`、`opencc/` 之类。
  public var alsoCopy: [FilePath]
  /// 上游 OpenCC 数据目录(资源 bundle 里的 `opencc/`),作为输出 `opencc/`
  /// 的垫底层:声明覆盖的位置不动,其余由上游补全——数据集可以整目录声明
  /// `opencc/` 拿走整个子树,也可以逐文件声明、由上游补齐其余。librime 按
  /// `<shared>/opencc/<名字>` 解析 simplifier 的配置。nil = 不垫底。
  ///
  /// 垫底所得计入声明集(清扫据此保留)。声明集非空即激活清扫:只给本项
  /// 而不给 `expected`/`alsoCopy` 的调用,输出目录里其余未声明文件会被清除
  /// (与完全零声明时"清扫全面禁用"不同)。
  public var upstreamOpenCC: FilePath?
  /// 以 INFO 而非 WARNING 级别记录日志。
  public var verbose: Bool

  public init(
    dataDirectory: FilePath,
    outputDirectory: FilePath,
    workDirectory: FilePath? = nil,
    mode: RimeDeployMode = .prebuild,
    expected: [FilePath] = [],
    alsoCopy: [FilePath] = [],
    upstreamOpenCC: FilePath? = nil,
    verbose: Bool = false
  ) {
    self.dataDirectory = dataDirectory
    self.outputDirectory = outputDirectory
    self.workDirectory = workDirectory
    self.mode = mode
    self.expected = expected
    self.alsoCopy = alsoCopy
    self.upstreamOpenCC = upstreamOpenCC
    self.verbose = verbose
  }
}

public struct RimeDeployOutcome: Sendable {
  /// 因数据不再声明而被清除的文件数。
  public let removedStaleFiles: Int
  /// 已声明并通过校验的产物数。
  public let verifiedArtifacts: Int
}

public struct RimeDeployError: Error, CustomStringConvertible {
  public let description: String

  init(_ description: String) {
    self.description = description
  }
}

/// 部署门:进程级 librime 状态与本地共享根的 async 串行域。
///
/// librime 的引擎状态(`RimeApi`、部署目录)进程级全局,`Rime.localShared`
/// 是它唯一的本地执行域——两个部署同时进行就会写进彼此的目录;根 actor 串行化
/// 的是单次调用,不是一轮部署的调用组,门以 FIFO 保证整轮原子。命令行工具一进程
/// 一次,永远遇不到;任何在进程内驱动它的东西(测试,或在多任务上部署的宿主)
/// 都会。await 只挂起协作线程,不占线程(形态同 RimeSessionGate)。
private final class DeploymentGate: Sendable {
  private struct State: Sendable {
    var busy = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func acquire() async {
    await withCheckedContinuation { continuation in
      state.withLock { state in
        if state.busy {
          state.waiters.append(continuation)
          return
        }
        state.busy = true
        // 置位与 resume 必须在同一临界区内:移出则解锁到 resume 之间可能
        // 被第三方 acquire 抢先(release 见空队列置 busy=false),双持有。
        continuation.resume()
      }
    }
  }

  func release() {
    let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
      if state.waiters.isEmpty {
        state.busy = false
        return nil
      }
      return state.waiters.removeFirst()  // busy 保持 true:所有权移交
    }
    next?.resume()
  }
}

private let deploymentGate = DeploymentGate()

/// 执行一次部署。
///
/// 任何失败都抛 `RimeDeployError`;其描述就是应展示给用户的信息。
///
/// 进程内的部署是串行的,见 `deploymentGate`。
public func runRimeDeploy(_ request: RimeDeployRequest) async throws -> RimeDeployOutcome {
  await deploymentGate.acquire()
  defer { deploymentGate.release() }

  // 声明名恒为相对:expected 相对 staging 根,alsoCopy 相对 dataDirectory。
  // 绝对名不能靠拼接折叠——子项按相对契约处理(FilePath 的拼接对绝对输入
  // 有 cd 语义,会替换基准而非追加),入口直接拒绝。
  for name in request.expected where name.isAbsolute {
    throw RimeDeployError("--expect names are relative to --out-dir, not absolute: \(name)")
  }
  for name in request.alsoCopy where name.isAbsolute {
    throw RimeDeployError("--also-copy names are relative to --data-dir, not absolute: \(name)")
  }

  let dataDir = try requireDirectory(request.dataDirectory, "--data-dir")
  let outDir = try makeDirectory(request.outputDirectory, "--out-dir")
  let workDir = try makeDirectory(
    request.workDirectory ?? FilePath(request.outputDirectory.string + "-work"), "--work-dir")
  // 路径校验先于部署:拼错的输入应当立即报错,而不是跑完一整轮编译。
  if let upstream = request.upstreamOpenCC {
    _ = try requireDirectory(upstream, "--upstream-opencc")
  }

  let traits = RimeTraits(
    sharedDataDir: dataDir.string,
    userDataDir: workDir.string,
    distributionName: rimeDeployToolName,
    distributionCodeName: rimeDeployToolName,
    distributionVersion: "1",
    appName: "rime.deploy",
    minLogLevel: request.verbose ? .info : .warning,
    logDir: "",
    stagingDir: outDir.appending("build").string)
  // prebuilt_data_dir 刻意不设置:它指向随发行版分发的**只读**目录,仅在
  // staging 中找不到资源时回退查询——不是本工具的写入目标,把它指向输出目录
  // 等于把只读缓存说成正在写入的东西。不设置时取 librime 默认的
  // <shared>/build——消费方把 shared_data_dir 指向本输出目录的根,编译产物
  // 正好落在 <shared>/build,即被 deployed 解析器自动兜底命中:这是把
  // staging 安排在 build/ 子目录的全部意义。
  // prebuilt_data_dir 刻意不设置(见上 traits 注释)。

  let root = Rime.localShared

  do {
    try await root.setup(with: traits)

    // 在部署模块加载之前挂上收集回调,以免漏掉任何一条:link 失败只出现在
    // glog 记录里(部署返回值仍为成功)。工具进程短命,sink 常驻即随进程退役。
    let firstError = FirstDeployError()
    let sinkInstalled = root.plugin.logSink()?.install { record in
      guard record.level == .error || record.level == .fatal else { return }
      let location = record.file.map { "[\($0):\(record.line)] " } ?? ""
      firstError.capture(location + record.message)
    }

    try await root.initializeDeployer(with: traits)

    // 复制 librime 在运行期而非构建期读取的数据:进数据集**根**,与
    // build/ 里的编译产物并列——消费方把 shared_data_dir 指向该根即可,
    // prebuilt(=<shared>/build)与 opencc/lua 等源数据同时可达。
    for name in request.alsoCopy {
      try copyThrough(name: name, from: dataDir, to: outDir)
    }

    let succeeded: Bool
    switch request.mode {
    case .prebuild:
      succeeded = try await root.prebuild()
    case .deploy:
      succeeded = try await root.deploy()
    }

    // 在调用方任务上等待,但 librime 仍可能持有工作线程状态。
    try await root.finalize()

    // 收集已到终局:一次根据最终结果与捕获的 glog 错误上报。link 失败会以
    // "成功"返回,捕获的 ERROR+ 与失败同等定性;上报先于产物检查——它解释
    // 了产物为何缺失。
    if sinkInstalled == nil {
      // 模块缺失:stderr 原样透传(未静音),glog 输出即现场,收集无从谈起。
      note(
        "this librime has no logsink module, so a schema whose config fails to "
          + "link cannot be detected; only the declared artifacts are checked")
      if !succeeded {
        throw RimeDeployError("\(request.mode.rawValue) failed; see the librime log above")
      }
    } else {
      // 模块在场:stderr 已被端点静音、logDir 为空无文件日志,捕获内容即详情。
      switch (succeeded, firstError.value) {
      case (true, nil):
        break
      case (false, nil):
        throw RimeDeployError(
          "\(request.mode.rawValue) failed; the deployment left no ERROR+ record to report")
      case (false, .some(let captured)):
        throw RimeDeployError(
          """
          \(request.mode.rawValue) failed. librime reported an error while deploying:
            \(captured)
          """)
      case (true, .some(let captured)):
        throw RimeDeployError(
          """
          librime reported an error while deploying, though deployment reported success:
            \(captured)

          这并不总会反映在部署结果里:配置无法 link 的 schema(无法解析的 \
          __include 或 __patch)会让该 schema 与其词典都不落盘,而整轮仍报成功。 \
          请修正数据;收集到的信息指出了失败的文件。
          """)
      }
    }
  } catch let error as RimeDeployError {
    throw error
  } catch {
    throw RimeDeployError("\(error)")
  }

  // 上游 OpenCC 全量集垫底:声明覆盖者不动,其余补全;复制所得并入声明集。
  // 复制在部署终局之后。
  let upstreamCopied =
    try request.upstreamOpenCC.map {
      try copyUpstreamOpenCC(from: $0, into: outDir, datasetProvided: Set(request.alsoCopy))
    } ?? []

  // expected 以 staging 根(build/)为基准;also-copy 与上游垫底在数据集根。
  // 三者合并构成输出目录的完整保留集。
  let stagedExpected = request.expected.map { FilePath("build").pushing($0) }
  let keeping = stagedExpected + request.alsoCopy + upstreamCopied
  let removed = try removeStaleFiles(in: outDir, keeping: keeping)

  let missing = missingArtifacts(in: outDir, expected: keeping)
  guard missing.isEmpty else {
    throw RimeDeployError(describeMissing(missing, in: outDir))
  }

  return RimeDeployOutcome(
    removedStaleFiles: removed, verifiedArtifacts: request.expected.count)
}

// MARK: - helpers

private func note(_ message: String) {
  FileHandle.standardError.write(Data("\(rimeDeployToolName): \(message)\n".utf8))
}

// 路径的两个类别:
//
// * `FilePath`(SystemPackage)——库内路径的**表示与词法计算**:构造、拼接
//   (pushing;对绝对输入有 cd 语义——替换基准而非追加,故声明名在入口处
//   拒绝绝对形式)、父目录(removingLastComponent,删到空路径或根为止)、
//   遍历产出、声明集与排序比较(不可比较,经 `.string` 定序)。纯词法、
//   值类型、不锚定 CWD、无 Foundation 桥接。相等性为原始字节比较(String
//   是 Unicode 规范化等价)——声明集与磁盘名须同形,混用 NFC/NFD 时同一
//   名字可互不命中。
// * `URL`(Foundation)——**文件系统边界**的两种用途:① FileManager 的
//   `at:` 形态调用(createDirectory/copyItem/removeItem/
//   contentsOfDirectory),经 `url(of:)` 转换;② 文件系统语境规范化
//   (相对路径按 CWD 绝对化 + `standardizedFileURL` 消解 `.`/`..`),
//   结果即刻折回 `FilePath`。
//
// 边界上仅余的 String 面,共三处:① `fileExists` 仅有 `atPath:` 形态;
// ② `enumerator` 取 `atPath:` 形态以直接获得相对条目(其 `at:` 形态产出
// 绝对 URL,还得再剥前缀);③ librime 的 C 结构体(RimeTraits)收
// `char*`。另有 `<out>-work` 默认工作目录名一处经 String 拼后缀(FilePath
// 无"给末段加后缀"的词法操作)。

private func url(of path: FilePath) -> URL {
  URL(fileURLWithPath: path.string)
}

/// 目标存在且是目录:nil = 不存在,false = 存在但非目录。
private func isDirectory(at path: FilePath) -> Bool? {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: path.string, isDirectory: &isDirectory) else {
    return nil
  }
  return isDirectory.boolValue
}

/// 目标存在(fileExists 仅有字符串形态,见类别说明)。
private func exists(_ path: FilePath) -> Bool {
  FileManager.default.fileExists(atPath: path.string)
}

private func requireDirectory(_ path: FilePath, _ flag: String) throws -> FilePath {
  guard let isDirectory = isDirectory(at: path) else {
    throw RimeDeployError("\(flag) does not exist: \(path)")
  }
  guard isDirectory else {
    throw RimeDeployError("\(flag) is not a directory: \(path)")
  }
  return FilePath(url(of: path).standardizedFileURL.path)
}

private func makeDirectory(_ path: FilePath, _ flag: String) throws -> FilePath {
  do {
    try FileManager.default.createDirectory(
      at: url(of: path), withIntermediateDirectories: true)
  } catch {
    throw RimeDeployError("cannot create \(flag) \(path): \(error.localizedDescription)")
  }
  return FilePath(url(of: path).standardizedFileURL.path)
}

private func copyThrough(name: FilePath, from dataDir: FilePath, to outDir: FilePath) throws {
  let source = dataDir.pushing(name)
  let destination = outDir.pushing(name)
  guard exists(source) else {
    throw RimeDeployError("--also-copy \(name): no such file in \(dataDir)")
  }
  do {
    let parent = destination.removingLastComponent()
    if !parent.isEmpty {
      try FileManager.default.createDirectory(
        at: url(of: parent), withIntermediateDirectories: true)
    }
    if exists(destination) {
      try FileManager.default.removeItem(at: url(of: destination))
    }
    try FileManager.default.copyItem(at: url(of: source), to: url(of: destination))
  } catch {
    throw RimeDeployError("cannot copy \(name) into \(outDir): \(error.localizedDescription)")
  }
}

/// 上游 OpenCC 数据垫底:把 `source`(资源 bundle 里的 `opencc/`)下的每个
/// 文件复制进输出目录的同名位置,声明覆盖的位置一律跳过;未声明的同名遗留
/// 物被上游覆盖。返回实际复制的相对路径(`opencc/` 前缀),计入声明集。
private func copyUpstreamOpenCC(
  from source: FilePath, into outDir: FilePath, datasetProvided: Set<FilePath>
) throws -> [FilePath] {
  var copied: [FilePath] = []
  for relative in relativeFilePaths(in: source).sorted(by: { $0.string < $1.string }) {
    // 点文件/点目录不垫底(与插件输入侧同规):bundle 混入的 .DS_Store 之类
    // 不该随全量集分发,更不该受声明集保护、永不清扫。
    guard !relative.components.contains(where: { $0.string.hasPrefix(".") }) else { continue }
    let name = FilePath("opencc").pushing(relative)
    guard !declarationsCover(name, in: datasetProvided) else { continue }
    let destination = outDir.pushing(name)
    do {
      let parent = destination.removingLastComponent()
      try FileManager.default.createDirectory(
        at: url(of: parent), withIntermediateDirectories: true)
      if exists(destination) {
        try FileManager.default.removeItem(at: url(of: destination))
      }
      try FileManager.default.copyItem(
        at: url(of: source.pushing(relative)), to: url(of: destination))
      copied.append(name)
    } catch {
      throw RimeDeployError(
        "cannot copy upstream opencc \(relative) into \(outDir): \(error.localizedDescription)")
    }
  }
  return copied
}

/// 声明集是否覆盖该相对路径:精确命中(also-copy 逐文件),或任一祖先目录被
/// 整目录声明(`opencc` 覆盖 `opencc/<名字>`)。上游垫底与清扫共用此判据:
/// 被声明覆盖的位置既不由上游覆盖,也不被清扫删除。
///
/// 沿 `removingLastComponent()` 逐级上溯,删到空路径或根为止——终止性由
/// API 承担(见 helpers 区的类别说明)。
private func declarationsCover(_ relative: FilePath, in declared: Set<FilePath>) -> Bool {
  var path = relative
  while true {
    if declared.contains(path) { return true }
    let parent = path.removingLastComponent()
    if parent == path || parent.isEmpty { return false }
    path = parent
  }
}

/// `directory` 下任意深度的全部文件,以相对路径表示(enumerator 取字符串
/// 形态以直接获得相对条目,见类别说明)。
public func relativeFilePaths(in directory: FilePath) -> [FilePath] {
  guard let walker = FileManager.default.enumerator(atPath: directory.string)
  else { return [] }
  var relative: [FilePath] = []
  while let entry = walker.nextObject() as? String {
    var isDirectory: ObjCBool = false
    let path = directory.string + "/" + entry
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else { continue }
    relative.append(FilePath(entry))
  }
  return relative
}

/// `directory` 下的全部目录,最深的在前——这样被清空的子目录先于其父目录
/// 被移除。
private func relativeDirectories(in directory: FilePath) -> [FilePath] {
  guard let walker = FileManager.default.enumerator(atPath: directory.string)
  else { return [] }
  var relative: [FilePath] = []
  while let entry = walker.nextObject() as? String {
    var isDirectory: ObjCBool = false
    let path = directory.string + "/" + entry
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { continue }
    relative.append(FilePath(entry))
  }
  return relative.sorted { $0.components.count > $1.components.count }
}

/// 清除输出目录里本次数据未声明的一切,返回清除的文件数。
///
/// librime 既不写也不删源已消失的产物,没有这一步它们就会留在输出目录里并
/// 随包分发。调用方声明过的文件绝不触碰:基于校验和复用最新产物正是编译器的
/// 本分,什么都没变的重新构建不应该重写任何东西。
///
/// 什么都没声明的调用方完全不做清除:声明是区分"产物"与"早于本次数据集的
/// 东西"的唯一依据,空的声明会让每个文件都显得陈旧——包括刚写出来的那些。
private func removeStaleFiles(in outDir: FilePath, keeping declared: [FilePath]) throws -> Int {
  guard !declared.isEmpty else { return 0 }
  let expected = Set(declared)
  var removed = 0
  for relative in relativeFilePaths(in: outDir).sorted(by: { $0.string < $1.string })
  where !declarationsCover(relative, in: expected) {
    let stale = outDir.pushing(relative)
    do {
      try FileManager.default.removeItem(at: url(of: stale))
      removed += 1
    } catch {
      throw RimeDeployError(
        "cannot remove the stale \(relative): \(error.localizedDescription)")
    }
  }
  for relative in relativeDirectories(in: outDir) {
    let path = outDir.pushing(relative)
    let contents = try? FileManager.default.contentsOfDirectory(
      at: url(of: path), includingPropertiesForKeys: nil)
    if contents?.isEmpty == true {
      try? FileManager.default.removeItem(at: url(of: path))
    }
  }
  return removed
}

private func missingArtifacts(in outDir: FilePath, expected: [FilePath]) -> [FilePath] {
  expected
    .filter { !exists(outDir.pushing($0)) }
    .sorted(by: { $0.string < $1.string })
}

private func describeMissing(_ missing: [FilePath], in outDir: FilePath) -> String {
  let listing = relativeFilePaths(in: outDir).sorted(by: { $0.string < $1.string })
  return """
    compilation reported success but these artifacts are missing:
    \(missing.map { "  " + $0.string }.joined(separator: "\n"))
    produced in \(outDir):
    \(listing.map { "  " + $0.string }.joined(separator: "\n"))

    A declared artifact is named after the file it came from, so the build can
    know it before running the compiler. librime names its output after the
    identifiers found *inside* the data, which means every name used in the
    data has to match the file it lives in:

      * a schema's schema_id must equal its file name
        (<id>.schema.yaml holds "schema_id: <id>"); it deploys to the
        same-named compiled configuration
      * the dictionary a schema names in translator/dictionary must equal
        that dictionary's file name (<id>.dict.yaml holds "name: <id>"); it
        compiles to <name>.table.bin and <name>.reverse.bin, plus a prism
        named after translator/prism, defaulting to the dictionary's name
      * a *.dict.yaml that no schema names in translator/dictionary produces
        nothing: one merged into another dictionary via import_tables lives
        on only inside that dictionary's table, and one nothing references
        stays a source file, so names declared for them cannot all exist
    """
}

/// 部署期 glog 首条 ERROR+ 记录的收集槽(记录回调并发,锁保护;只进不改)。
private final class FirstDeployError: Sendable {
  private let slot = OSAllocatedUnfairLock<String?>(initialState: nil)

  var value: String? { slot.withLock { $0 } }

  func capture(_ text: String) {
    slot.withLock { if $0 == nil { $0 = text } }
  }
}
