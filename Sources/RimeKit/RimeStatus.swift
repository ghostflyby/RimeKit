// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import RimeC

public struct RimeStatus: Sendable, Codable {
  public let schemaID: String
  public let schemaName: String
  public let isDisabled: Bool
  public let isComposing: Bool
  public let isASCIIMode: Bool
  public let isFullShape: Bool
  public let isSimplified: Bool
  public let isTraditional: Bool
  public let isASCIIPunctuation: Bool
}

extension RimeStatus {
  fileprivate init(rawValue: rime_status_t) {
    schemaID = String(cString: rawValue.schema_id)
    schemaName = String(cString: rawValue.schema_name)
    isDisabled = rawValue.is_disabled
    isComposing = rawValue.is_composing
    isASCIIMode = rawValue.is_ascii_mode
    isFullShape = rawValue.is_full_shape
    isSimplified = rawValue.is_simplified
    isTraditional = rawValue.is_traditional
    isASCIIPunctuation = rawValue.is_ascii_punct
  }
}

extension RimeSession {
  public var status: RimeStatus? {
    get async throws {
      try await root.status(for: sessionID)
    }
  }
}

extension Rime {
  func engineStatus(for sessionID: RimeSessionID) throws(RimeError) -> RimeStatus? {
    var status = rime_status_t.rimeStructInit()
    defer { _ = rimeApi.free_status(&status) }
    guard rimeApi.get_status(sessionID.rawValue, &status) else {
      return nil
    }
    return RimeStatus(rawValue: status)
  }
}
