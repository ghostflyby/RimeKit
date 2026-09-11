// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

@testable import RimeKit

/// librime 键值约定(Squirrel 的 MacOSKeyCodes.swift 同源事实):
/// keycode = X11 keysym(`src/rime/key_table.h` 内建 `include/X11/keysym.h`);
/// modifier 掩码亦为 X11 布局(kShiftMask=1<<0、kControlMask=1<<2、kAltMask=1<<3…)。
enum Key {
  /// 可打印 ASCII(latin 小写字母、数字等)的 keysym 即其 ASCII 码。
  static func ascii(_ character: Character) -> Int32 {
    guard let scalar = character.asciiValue else {
      fatalError("测试只键入可打印 ASCII,收到:\(character)")
    }
    return Int32(scalar)
  }

  static let backspace: Int32 = 0xFF08  // XK_BackSpace
  static let escape: Int32 = 0xFF1B  // XK_Escape
  static let `return`: Int32 = 0xFF0D  // XK_Return
  static let pageUp: Int32 = 0xFF55  // XK_Page_Up
  static let pageDown: Int32 = 0xFF56  // XK_Page_Down
}

/// librime `RimeModifier` 掩码(key_table.h 数值)。
enum ModifierMask {
  static let shift: Int32 = 1 << 0
  static let capsLock: Int32 = 1 << 1
  static let control: Int32 = 1 << 2
  static let alt: Int32 = 1 << 3
  static let release: Int32 = 1 << 30
}
