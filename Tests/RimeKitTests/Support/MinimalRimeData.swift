// SPDX-License-Identifier: MPL-2.0
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// 自造最小方案数据(librime gtest 的 data/test/ 范式:不依赖 rime-data/luna_pinyin)。
///
/// 确定性设计:
/// - `table_translator` 直查表码,`enable_sentence/enable_user_dict/enable_completion`
///   全关 → 候选序 = 词典权重降序,与运行历史无关;
/// - 引擎件仅保留 `ascii_composer/speller/selector/navigator/express_editor`,
///   无标点/识别器等带内建默认值的部件,行为面最小化;
/// - 两个方案共用同一词典,alt 方案只为 schema 切换/通知测试服务。
enum MinimalRimeData {
  static let primarySchemaID = "rimekit_test"
  static let primarySchemaName = "测试方案"
  static let altSchemaID = "rimekit_alt"
  static let altSchemaName = "备用方案"

  /// 菜单页大小(schema `menu/page_size`)。
  static let pageSize = 5

  /// 码 `nihao` 的候选,权重降序即候选序。
  static let nihaoCandidates = ["你好", "泥号", "拟好"]
  /// 码 `ceshi` 的候选。
  static let ceshiCandidates = ["测试"]
  /// 码 `mmmm` 的候选:12 条 → 5/5/2 三页,覆盖翻页/末页判定。
  static let mmmmCandidates = ["密", "蜜", "觅", "谧", "嘧", "糜", "麋", "靡", "脒", "汨", "咪", "咩"]

  /// 把全部夹具文件写入 `userDir`(它同时充当 sharedDataDir——夹具自包含,无共享数据)。
  static func write(into userDir: URL) throws {
    let files: [(String, String)] = [
      ("default.yaml", defaultYAML),
      ("\(primarySchemaID).schema.yaml", schemaYAML(id: primarySchemaID, name: primarySchemaName)),
      ("\(altSchemaID).schema.yaml", schemaYAML(id: altSchemaID, name: altSchemaName)),
      ("\(primarySchemaID).dict.yaml", dictYAML),
    ]
    for (name, content) in files {
      try content.write(
        to: userDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
  }

  // MARK: - 文件内容

  static let defaultYAML = """
    config_version: "1"

    schema_list:
      - schema: \(primarySchemaID)
      - schema: \(altSchemaID)

    switcher:
      hotkeys: []
    """

  static func schemaYAML(id: String, name: String) -> String {
    """
    schema:
      schema_id: \(id)
      name: \(name)
      version: "1"

    switches:
      - name: ascii_mode
        states: [ 中文, 西文 ]
        reset: 0
      - name: full_shape
        states: [ 半角, 全角 ]
        reset: 0

    engine:
      processors:
        - ascii_composer
        - speller
        - selector
        - navigator
        - express_editor
      segmentors:
        - abc_segmentor
      translators:
        - table_translator

    speller:
      alphabet: zyxwvutsrqponmlkjihgfedcba

    menu:
      page_size: \(pageSize)

    translator:
      dictionary: \(primarySchemaID)
      enable_user_dict: false
      enable_sentence: false
      enable_completion: false
    """
  }

  /// 词条:文本 <TAB> 码 <TAB> 权重;同码候选按权重降序进入候选表。
  static let dictYAML: String = {
    var entries: [String] = [
      "你好\tnihao\t9000",
      "泥号\tnihao\t5000",
      "拟好\tnihao\t1000",
      "测试\tceshi\t8000",
      "你\tni\t8000",
      "泥\tni\t5000",
    ]
    for (offset, text) in mmmmCandidates.enumerated() {
      entries.append("\(text)\tmmmm\t\(12000 - offset * 1000)")
    }
    return """
      ---
      name: \(primarySchemaID)
      version: "1"
      sort: original
      ...
      \(entries.joined(separator: "\n"))
      """
  }()
}
