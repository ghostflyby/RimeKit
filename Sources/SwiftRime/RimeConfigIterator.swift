// TODO: - RimeConfigIterator
public struct RimeConfigIterator: AsyncIteratorProtocol, Sendable {
	internal let handle: ObjectHandle<RimeConfigIterator>
	internal let engine: any Rime

	public mutating func next() async throws -> RimeConfig? {
		nil
	}

	public mutating func next(isolation actor: isolated (any Actor)?) async
		-> RimeConfig?
	{
		nil
	}

}

public class RimeCandidateIterator: AsyncIteratorProtocol {
	internal init(
		handle: ObjectHandle<RimeCandidateIterator>, value: RimeCandidate? = nil, engine: any Rime
	) {
		self.handle = handle
		self.value = value
		self.engine = engine
	}

	internal let handle: ObjectHandle<RimeCandidateIterator>
	internal var value: RimeCandidate?
	internal let engine: any Rime

	public func next() async throws -> RimeCandidate? {
		let candidate = value
		self.value = await engine.advanceCandidateIterator(handle)
		return candidate
	}

	public func next(isolation actor: isolated (any Actor)?) async
		-> RimeCandidate?
	{
		let candidate = value
		self.value = await engine.advanceCandidateIterator(handle)
		return candidate
	}

	deinit {
		let ptr = handle
		let engine = engine
		Task.detached {
			await engine.endCandidateIterator(ptr)
		}
	}

}
