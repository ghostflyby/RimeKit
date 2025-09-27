public struct RimeConfigLocation: Codable, Sendable {
	let index: Int32
	let key: String?
	let path: String?
}

public class RimeConfigIterator: AsyncIteratorProtocol {
	internal let handle: ObjectHandle<RimeConfigIterator>
	internal let engine: any Rime

	internal init(handle: ObjectHandle<RimeConfigIterator>, engine: any Rime) {
		self.handle = handle
		self.engine = engine
	}

	public func next() async throws -> RimeConfigLocation? {
		await engine.advanceConfigIterator(handle)
	}

	public func next(isolation actor: isolated (any Actor)?) async
		-> RimeConfigLocation?
	{
		await engine.advanceConfigIterator(handle)
	}

	deinit {
		let ptr = handle
		let engine = engine
		Task.detached {
			await engine.endConfigIterator(ptr)
		}
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
