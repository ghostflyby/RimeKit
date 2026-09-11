// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing

@testable import RimeKit

/// 方案面:方案表、切换、状态标签(Squirrel 依赖 `get_schema_list`/
/// `select_schema`/`get_state_label(_abbreviated)` 驱动菜单与状态弹窗)。
/// `RimeSession` 为 `~Copyable`:观察值一律先取出局部值再进断言宏。
@Suite struct SchemaTests {
  @Test(arguments: RimeBackend.allCases)
  func schemaListMatchesFixture(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let items = try await session.schemas
    #expect(
      items.map(\.schemaID) == [MinimalRimeData.primarySchemaID, MinimalRimeData.altSchemaID])
    #expect(
      items.map(\.name) == [MinimalRimeData.primarySchemaName, MinimalRimeData.altSchemaName])
  }

  /// 新建会话继承**进程级"最后选择的方案"**——librime 会把选择持久化到
  /// user.yaml,并行套件切换方案时,新会话可能以非默认方案起步(实证,多次复现)。
  /// 先显式归位主方案(选择施加于本会话,此后断言确定),再验证方案选择语义。
  @Test(arguments: RimeBackend.allCases)
  func newSessionSchemaIsSelectableAndStable(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let sessionID = session.sessionID
    _ = try await session.selectSchema(id: MinimalRimeData.primarySchemaID)

    let currentSchema = try await env.root.currentSchema(for: sessionID)
    let status = try await session.status
    #expect(currentSchema == MinimalRimeData.primarySchemaID)
    #expect(status?.schemaID == MinimalRimeData.primarySchemaID)
    #expect(status?.schemaName == MinimalRimeData.primarySchemaName)
  }

  @Test(arguments: RimeBackend.allCases)
  func selectAltSchemaAndBack(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let sessionID = session.sessionID

    let selected = try await session.selectSchema(id: MinimalRimeData.altSchemaID)
    #expect(selected == true)
    let altCurrent = try await env.root.currentSchema(for: sessionID)
    let altStatus = try await session.status
    #expect(altCurrent == MinimalRimeData.altSchemaID)
    #expect(altStatus?.schemaID == MinimalRimeData.altSchemaID)
    #expect(altStatus?.schemaName == MinimalRimeData.altSchemaName)

    // alt 方案与主方案共用词典:输入行为一致。
    _ = try await session.typeKeys("nihao")
    let texts = try await session.candidateTexts
    #expect(texts == MinimalRimeData.nihaoCandidates)
    try await session.clearComposition()

    let selectedBack = try await session.selectSchema(id: MinimalRimeData.primarySchemaID)
    #expect(selectedBack == true)
    let currentSchema = try await env.root.currentSchema(for: sessionID)
    #expect(currentSchema == MinimalRimeData.primarySchemaID)
  }

  @Test(arguments: RimeBackend.allCases)
  func selectSchemaBoolDoesNotValidateSchemaID(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    // librime 1.16.1 rime_api_impl.h(DEPRECATED 路径):select_schema 只要会话存在
    // 即返回 true,不校验方案是否存在——Bool 不是有效性信号。
    // 已知方案的端到端切换语义由 selectAltSchemaAndBack 覆盖。
    let session = try await env.makeSession()
    let handled = try await session.selectSchema(id: "rimekit_nonexistent")
    #expect(handled == true)
  }

  @Test(arguments: RimeBackend.allCases)
  func stateLabelsFromSwitches(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let asciiOff = try await session.stateLabel(for: "ascii_mode", state: .off)
    let asciiOn = try await session.stateLabel(for: "ascii_mode", state: .on)
    let shapeOff = try await session.stateLabel(for: "full_shape", state: .off)
    let shapeOn = try await session.stateLabel(for: "full_shape", state: .on)
    let unknown = try await session.stateLabel(for: "nonexistent_option", state: .on)
    #expect(asciiOff == "中文")
    #expect(asciiOn == "西文")
    #expect(shapeOff == "半角")
    #expect(shapeOn == "全角")
    // 未知选项:无标签(nil),非错误。
    #expect(unknown == nil)
  }

  @Test(arguments: RimeBackend.allCases)
  func abbreviatedStateLabelsAvailable(backend: RimeBackend) async throws {
    let env = try await RimeTestEnvironment.bootstrapped(backend: backend)
    let session = try await env.makeSession()
    let label = try await session.stateLabel(for: "ascii_mode", state: .on, abbreviated: true)
    #expect(label?.isEmpty == false)
  }
}
