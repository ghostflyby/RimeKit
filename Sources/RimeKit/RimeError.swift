// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Typed error surface of every `Rime` protocol requirement.
///
/// Replaces the force-unwrap crash paths: stale or foreign `ObjectHandle`s,
/// unusable engines and failed deployments surface as values of this type
/// instead of traps, and cross the XPC wire via SwiftXPC's typed-throws
/// decoding (see Docs/XPC-BlueGreen-Refactor-Plan.md §3.3).
public enum RimeError: Error, Sendable, Hashable {
  /// A handle is not present in the engine's registry (stale after
  /// `finalize`, foreign, or from another engine instance).
  case invalidHandle(kind: HandleKind, id: UUID)
  /// The session id is not in librime's process-local session table.
  case sessionNotFound(RimeSessionID)
  /// The engine was used before `initialize(with:)` or after `finalize()`.
  case engineNotInitialized
  /// The engine is inside a maintenance window and refused the call.
  case maintenanceMode
  /// A deployer operation reported failure; `operation` names it.
  case deployFailed(operation: String)
  /// A call was rejected before reaching librime.
  case invalidArgument(String)
  /// The loaded librime does not provide the requested API entry.
  case apiUnavailable(String)
}

public enum HandleKind: Sendable, Hashable {
  case config
  case configIterator
  case candidateIterator
}
