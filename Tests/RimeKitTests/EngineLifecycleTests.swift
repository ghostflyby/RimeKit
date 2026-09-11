// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import RimeKit

/// 引擎生命周期与运维面(参考:librime `rime_test_main.cc` 的 Environment 一次性
/// setup/initialize;Squirrel `setupRime`/`startRime` 后的目录与部署状态)。
@Suite struct EngineLifecycleTests {
  @Test(arguments: RimeBackend.allCases)
  func versionIsNonEmpty(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    #expect(try await env.root.version().isEmpty == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func opsSurfaceAnswers(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    #expect(try await env.root.healthCheck() == true)
    #expect(try await env.root.serviceVersion().hasPrefix("rimekit/"))
  }

  @Test(arguments: RimeBackend.allCases)
  func directoriesReflectTraits(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let userDirectory = env.userDirectory.path
    #expect(try await env.root.userDataDirectory() == userDirectory)
    // 夹具自包含:sharedDataDir 也指向夹具目录。
    #expect(try await env.root.sharedDataDirectory() == userDirectory)
    // 配置/部署分离(§9):staging 由目录布局决定(分代隔离),不在配置目录之内。
    // 注:logDir 只入不出(traits 可设,无 getter),无法在此直接断言。
    #expect(try await env.root.stagingDirectory() == env.layout.stagingDirectory.path)
    #expect(try await env.root.prebuiltDataDirectory().isEmpty == false)
  }

  @Test(arguments: RimeBackend.allCases)
  func maintenanceWindowClosedAfterBootstrap(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    #expect(try await env.root.isMaintenanceMode() == false)
    // 注意:prebuild()/deploy()/deploySchema(已知方案) 会触发部署任务乃至维护窗口,
    // 属全局变更性操作,只允许发生在 bootstrap 内;在并行套件共享引擎的前提下,
    // 测试体内调用它们会污染其它套件(维护期会话调用静默 false,§3.7 规则 d)。
  }

  /// deploy/prebuild/deploySchema 族的失败/重编译语义无法在共享引擎上安全探测:
  /// 即使是"未知方案"的失败任务也会短暂置起维护态(实证:并行套件的会话调用
  /// 随即静默 false)。部署侧行为留给 remote 后端阶段的隔离环境测试。

  @Test(arguments: RimeBackend.allCases)
  func identitySmoke(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    // 身份/同步目录接口只要求可用不崩溃(取值依赖宿主安装状态,不作强断言)。
    _ = try await env.root.userID()
    _ = try await env.root.userDataSyncDirectory()
    _ = try await env.root.syncDirectory()
  }
}
