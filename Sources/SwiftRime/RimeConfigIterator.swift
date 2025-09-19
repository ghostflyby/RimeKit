public struct RimeConfigIterator: AsyncIteratorProtocol {
	public typealias Element = RimeConfig
	public typealias Failure = any Error

	public mutating func next() async throws -> Element? {
		nil
	}

	public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure)
		-> Element?
	{
		nil
	}

}

public struct RimeCandidateIterator: AsyncIteratorProtocol {
	public typealias Element = RimeCandidate
	public typealias Failure = any Error

	public mutating func next() async throws -> Element? {
		nil
	}

	public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure)
		-> Element?
	{
		nil
	}

}
