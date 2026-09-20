// SPDX-FileCopyrightText: 2025-2026 ghostflyby
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// 会话同步门面的消费契约:输入法宿主面向此协议编程,测试以普通对象
/// 伪造(不触碰 librime)。`RimeSession` 为唯一生产遵循。
///
/// 全部方法为**阻塞调用**:当前线程等待引擎往返完成(输入法回调本就是
/// 同步契约,阻塞落在调用方线程——该线程本就要求等待);默认时限
/// 10s,超时抛 `RimeSessionError.timedOut`(内部操作继续,门随后释放)。
/// 事务方法在单次门持有内完成多调用分组,对其他事务不可见。
public protocol RimeSessionProtocol: AnyObject, Sendable {
  var sessionID: RimeSessionID { get }

  /// 按键事务:processKey + 提交/组字快照组装。
  func keyTransaction(keyCode: Int32, modifierMask: Int32) throws -> RimeKeyTransactionResult

  /// 失焦/收起事务:组字态下 commitComposition 并取回提交文本;
  /// 非组字态返回 nil(无副作用)。
  func blurTransaction() throws -> RimeCommit?

  /// 点选当前页候选(页内下标),返回事务输出。
  func selectCandidateTransaction(onCurrentPage index: Int) throws -> RimeKeyTransactionResult

  /// 翻页事务,返回事务输出。
  func pageTransaction(_ direction: RimePageDirection) throws -> RimeKeyTransactionResult

  /// 弹性取数:枚举**全量候选**(脱离引擎分页)并返回引擎高亮的全省
  /// 下标——消费方以自身窗口(定宽、任意容量)切片展示。
  func candidatesTransaction() throws -> RimeElasticCandidates

  /// 会话失效自愈核验:底层会话是否仍存在于引擎会话表
  /// (服务重启/引擎重初始化后旧 id 失效,消费方据此重建)。
  func sessionExists() throws -> Bool

  /// 全局下标点选(跨页自动定位),返回事务输出——弹性窗口内的词
  /// 不在引擎当前页,须用全局下标。
  func selectCandidateGlobalTransaction(at index: Int) throws -> RimeKeyTransactionResult

  /// 会话选项(librime option)。
  func setOption(_ option: String, value: Bool) throws

  /// 协调失效:从注册表移除并销毁底层会话(返回后该会话在引擎中已不存在)。
  /// 失效后一切事务抛 `RimeSessionError.invalidated`;消费方应丢弃引用并
  /// 按当前活跃根重建。
  func invalidate() async
}
