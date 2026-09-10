import Testing

@testable import RimeKit

/// 全局通知(Squirrel `notificationHandler` 消费的四类消息中的三类:
/// deploy 进度、option 状态、schema 切换;property 通知需保留属性约定,暂不覆盖)。
@Suite struct NotificationTests {
  let env: RimeTestEnvironment
  init() async throws { env = try await RimeTestEnvironment.bootstrapped() }

  @Test func bootstrapDeployReportedSuccess() async throws {
    let values = env.notifications.deployValues
    #expect(values.contains("success"))
    #expect(values.contains("failure") == false)
    // 部署进度从 start 开始(rime_api.h 契约:session_id=0,值域 start/success/failure)。
    #expect(values.first == "start")
  }

  @Test func optionNotificationCarriesSessionAndValue() async throws {
    let session = try await env.makeSession()
    let sessionID = session.sessionID
    let log = env.notifications

    try await session.setOption("ascii_mode", value: true)
    let turnedOn = await log.waitFor {
      $0.session == sessionID && $0.type == .option && $0.value == "ascii_mode"
    }
    #expect(turnedOn)

    try await session.setOption("ascii_mode", value: false)
    let turnedOff = await log.waitFor {
      $0.session == sessionID && $0.type == .option && $0.value == "!ascii_mode"
    }
    #expect(turnedOff)
  }

  @Test func schemaNotificationOnSwitch() async throws {
    let session = try await env.makeSession()
    let sessionID = session.sessionID
    let log = env.notifications

    let selected = try await session.selectSchema(id: MinimalRimeData.altSchemaID)
    #expect(selected == true)
    let altNotified = await log.waitFor {
      $0.session == sessionID && $0.type == .schema
        && $0.value.hasPrefix("\(MinimalRimeData.altSchemaID)/")
    }
    #expect(altNotified)

    let selectedBack = try await session.selectSchema(id: MinimalRimeData.primarySchemaID)
    #expect(selectedBack == true)
    let primaryNotified = await log.waitFor {
      $0.session == sessionID && $0.type == .schema
        && $0.value.hasPrefix("\(MinimalRimeData.primarySchemaID)/")
    }
    #expect(primaryNotified)
  }
}
