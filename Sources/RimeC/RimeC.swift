// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// librime C API 的包内转出口。
///
/// librime-xcframework 的 C 模块名为 `Rime`,与 RimeKit 的分布式 actor `Rime` 同名:
/// RimeKit 内本地类型遮蔽同名模块,`Rime.` 模块限定不可用。本目标自身不含 `Rime`
/// 类型,在此 `@_exported` 转出 C 模块——经 `import RimeC` 后,非限定 C 名直接可见,
/// 撞名 C 类型以 `RimeC.` 限定访问,不受遮蔽影响。
@_exported import Rime
