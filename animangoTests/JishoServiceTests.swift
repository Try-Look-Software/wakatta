import Foundation
import Testing
@testable import animango

/// Stubs URLSession traffic so no test touches the network, and records when each request arrived.
final class StubJishoProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [Date] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }

    static var times: [Date] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(Date())
        Self.lock.unlock()

        let body = Data("{\"data\":[]}".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Serialized because the stub records into shared static state.
@Suite(.serialized)
struct JishoServiceTests {

    private func makeService() -> JishoService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubJishoProtocol.self]
        StubJishoProtocol.reset()
        return JishoService(client: APIClient(session: URLSession(configuration: config)))
    }

    @Test func secondRequestWaitsAtLeastOneSecond() async throws {
        let service = makeService()

        _ = try await service.searchWords(keyword: "食べる")
        _ = try await service.searchWords(keyword: "飲む")

        let times = StubJishoProtocol.times
        try #require(times.count == 2)
        // Small tolerance for clock/scheduler rounding.
        #expect(times[1].timeIntervalSince(times[0]) >= 0.99)
    }

    @Test func consecutiveRequestsAreEachSpacedAtLeastOneSecond() async throws {
        let service = makeService()

        for keyword in ["a", "b", "c"] {
            _ = try await service.searchWords(keyword: keyword)
        }

        let times = StubJishoProtocol.times
        try #require(times.count == 3)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= 0.99)
        }
    }

    @Test func firstRequestIsNotDelayed() async throws {
        let service = makeService()
        let start = Date()

        _ = try await service.searchWords(keyword: "食べる")

        #expect(Date().timeIntervalSince(start) < 0.9)
    }

    @Test func requestAfterLongIdleIsNotDelayed() async throws {
        let service = makeService()
        _ = try await service.searchWords(keyword: "a")
        try await Task.sleep(nanoseconds: 1_100_000_000)

        let start = Date()
        _ = try await service.searchWords(keyword: "b")

        #expect(Date().timeIntervalSince(start) < 0.9)
    }
}
