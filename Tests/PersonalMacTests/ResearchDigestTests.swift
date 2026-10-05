import Foundation
import PersonalCore
import XCTest
@testable import PersonalMac

private final class DigestMock: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        var replies: [(Int, [String: String], Data)] = []
        var requests: [URLRequest] = []
        var delay: TimeInterval = 0
        func reset(_ replies: [(Int, [String: String], Data)], delay: TimeInterval = 0) {
            lock.lock(); defer { lock.unlock() }; self.replies = replies; requests = []; self.delay = delay
        }
        func next(_ request: URLRequest) -> (Int, [String: String], Data, TimeInterval) {
            lock.lock(); defer { lock.unlock() }; requests.append(request)
            let next = replies.isEmpty ? (500, [:], Data()) : replies.removeFirst()
            return (next.0, next.1, next.2, delay)
        }
        func captured() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, body, delay) = Self.state.next(request)
        let send: @Sendable () -> Void = { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: send) } else { send() }
    }
    override func stopLoading() {}
}

final class ResearchDigestTests: XCTestCase {
    private func configuration() -> LaboratoryConfiguration {
        var config = LaboratoryConfiguration(); config.enabled = true; config.baseURL = "https://research.example.org/api"; return config
    }
    private func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("docs/BIORA_DAILY_RESEARCH_EXAMPLE.json"))
    }
    private func mutated(_ transform: (inout [String: JSONValue]) -> Void) throws -> Data {
        var root = try JSONDecoder().decode(JSONValue.self, from: fixture()).object!
        transform(&root); return try JSONEncoder().encode(JSONValue.object(root))
    }
    private func client() -> ResearchDigestClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DigestMock.self]
        return ResearchDigestClient(session: URLSession(configuration: config))
    }
    private func directory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/TestWorkspaces/research-\(UUID())")
    }
    @MainActor private func store(_ directory: URL) throws -> PersonalStore {
        let store = PersonalStore(directory: directory, demo: false)
        try store.commit { $0.language = .english; $0.laboratory = configuration() }
        return store
    }
    func testValidGraphHasDeepTreeDiscussionAndTraceableSources() throws {
        let digest = try DailyResearchDigest.decode(fixture())
        let graph = try digest.materialize(language: .english)
        XCTAssertEqual(graph.mainline.count, 2); XCTAssertEqual(graph.mainline.last?.role, .discussion)
        XCTAssertEqual(graph.atomicExperiments.count, 2)
        XCTAssertTrue(graph.claims.allSatisfy { $0.sourceNote.contains("https://example.org/fictional-paper") })
        XCTAssertFalse(graph.detail.contains("SHA-256")); XCTAssertFalse(graph.claims.contains { !$0.experimentIDs.isEmpty })
        XCTAssertNoThrow(try graph.validated(experimentIDs: []))
    }
    func testStrictFieldsMetadataVersionLanguageAndSourceValidation() throws {
        for data in [try mutated { $0["extra"] = .string("no") },
                     try mutated { $0.removeValue(forKey: "revision") }] {
            XCTAssertThrowsError(try DailyResearchDigest.decode(data))
        }
        for (key, value): (String, JSONValue) in [("schema_version", .number(2)), ("language", .string("fr")), ("date", .string("2026-02-30")), ("revision", .number(0)), ("published_at", .string("invalid"))] {
            let digest = try DailyResearchDigest.decode(mutated { $0[key] = value })
            XCTAssertThrowsError(try digest.materialize(language: .english))
        }
        let chinese = try DailyResearchDigest.decode(mutated { $0["language"] = .string("zh-Hans"); $0["title"] = .string("中文研究摘要") })
        XCTAssertNoThrow(try chinese.materialize(language: .chinese))
        XCTAssertThrowsError(try chinese.materialize(language: .english))
        let unsafe = try DailyResearchDigest.decode(mutated { root in
            var sources = root["sources"]!.array!; var source = sources[0].object!; source["url"] = .string("file:///etc/passwd")
            sources[0] = .object(source); root["sources"] = .array(sources)
        })
        XCTAssertThrowsError(try unsafe.materialize(language: .english))
        XCTAssertThrowsError(try DailyResearchDigest.decode(Data(repeating: 32, count: DailyResearchDigest.maximumBytes + 1)))
    }
    func testMissingCitationsOrphansDirectMainlineAndCyclesRejected() throws {
        let noCitations = try DailyResearchDigest.decode(mutated { $0["citations"] = .array([]) })
        XCTAssertThrowsError(try noCitations.materialize(language: .english))
        for mutation in ["orphan", "direct", "cycle", "page"] {
            let data = try mutated { root in
                var graph = root["graph"]!.object!
                if mutation == "orphan" { graph["claim_links"] = .array(Array(graph["claim_links"]!.array!.dropFirst())) }
                if mutation == "direct" {
                    var edges = graph["evidence_links"]!.array!; var edge = edges[0].object!; edge["claim_key"] = .string("result1")
                    edges[0] = .object(edge); graph["evidence_links"] = .array(edges)
                }
                if mutation == "cycle" {
                    var edges = graph["claim_links"]!.array!; var edge = edges[0].object!
                    edge["from_key"] = .string("result1"); edge["to_key"] = .string("local"); edges.append(.object(edge)); graph["claim_links"] = .array(edges)
                }
                if mutation == "page" {
                    var citations = root["citations"]!.array!; var citation = citations[0].object!; citation["page"] = .number(99)
                    citations[0] = .object(citation); root["citations"] = .array(citations)
                }
                root["graph"] = .object(graph)
            }
            XCTAssertThrowsError(try DailyResearchDigest.decode(data).materialize(language: .english), mutation)
        }
    }
    func testSecureRequestIsReadOnlyScopedAndUsesExactQuery() throws {
        let config = configuration()
        let request = try ResearchDigestClient.request(configuration: config, date: "2026-10-02", language: .english, token: "server-token", etag: "\"v1\"")
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.path, "/api/v1/research/daily")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query, ["date": "2026-10-02", "timezone": "Asia/Shanghai", "language": "en", "feed": "default"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer server-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertThrowsError(try ResearchDigestClient.request(configuration: config, date: "2026-02-30", language: .english, token: nil, etag: nil))
        XCTAssertThrowsError(try ResearchDigestClient.request(configuration: config, date: "2026-10-02", language: .english, token: "key\nheader", etag: nil))
        var disabled = config; disabled.enabled = false
        XCTAssertThrowsError(try ResearchDigestClient.request(configuration: disabled, date: "2026-10-02", language: .english, token: nil, etag: nil))
        for address in ["http://localhost:8000", "https://user:secret@example.org", "https://example.org?token=secret", "https://example.org/#x", "file:///tmp/feed", "https://example.org/a/../b", "https://example.org/%2e%2e"] {
            var bad = config; bad.baseURL = address; XCTAssertThrowsError(try bad.serverURL(), address)
        }
    }
    func testCacheAndCredentialIdentityNeverCrossesServersFeedsLanguagesOrWorkspaces() throws {
        let config = configuration(), directory = directory()
        let base = try ResearchDigestClient.key(configuration: config, date: "2026-10-02", language: .english)
        var changed = config; changed.feed = "other"
        XCTAssertNotEqual(base, try ResearchDigestClient.key(configuration: changed, date: "2026-10-02", language: .english))
        XCTAssertNotEqual(base, try ResearchDigestClient.key(configuration: config, date: "2026-10-02", language: .chinese))
        changed = config; changed.baseURL = "https://other.example.org/api"
        XCTAssertNotEqual(try ResearchDigestClient.tokenAccount(configuration: config, directory: directory), try ResearchDigestClient.tokenAccount(configuration: changed, directory: directory))
        XCTAssertNotEqual(try ResearchDigestClient.tokenAccount(configuration: config, directory: directory), try ResearchDigestClient.tokenAccount(configuration: config, directory: directory.appendingPathComponent("other")))
        XCTAssertEqual(config.day(ISO8601DateFormatter().date(from: "2026-10-01T16:05:00Z")!), "2026-10-02")
    }
    func testClientDownloadConditionalMissingAuthenticationMimeAndMismatch() async throws {
        let config = configuration(), service = client()
        DigestMock.state.reset([(200, ["Content-Type": "application/json", "ETag": "\"v1\""], try fixture())])
        let result = try await service.fetch(configuration: config, date: "2026-10-02", language: .english, token: nil, etag: nil)
        guard case .downloaded(let digest, _, let etag) = result else { return XCTFail("No download") }
        XCTAssertEqual(digest.revision, 1); XCTAssertEqual(etag, "\"v1\"")
        for status in [202, 204, 404] {
            DigestMock.state.reset([(status, ["Retry-After": "120"], Data())])
            guard case .notPublished(let retry) = try await service.fetch(configuration: config, date: "2026-10-02", language: .english, token: nil, etag: nil) else { return XCTFail("No pending status") }
            XCTAssertEqual(retry, 120)
        }
        DigestMock.state.reset([(304, [:], Data())])
        guard case .notModified = try await service.fetch(configuration: config, date: "2026-10-02", language: .english, token: nil, etag: "\"v1\"") else { return XCTFail("No 304") }
        for (status, headers, data) in [(401, [:], Data()), (403, [:], Data()), (429, ["Retry-After": "120"], Data()), (500, [:], Data()), (302, ["Location": "https://other.example.org"], Data()), (304, [:], Data()), (200, ["Content-Type": "text/html"], Data()), (200, ["Content-Type": "application/json", "Content-Length": "2000001"], Data()), (200, ["Content-Type": "application/json"], try mutated { $0["date"] = .string("2026-10-01") })] {
            DigestMock.state.reset([(status, headers, data)])
            do { _ = try await service.fetch(configuration: config, date: "2026-10-02", language: .english, token: nil, etag: nil); XCTFail("Expected rejection: \(status)") } catch {}
        }
    }
    @MainActor func testCachePersistenceDoesNotAlterPersonalRecordsAnd304PreservesNodeIDs() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir), original = store.workspace, service = client()
        DigestMock.state.reset([(200, ["Content-Type": "application/json", "ETag": "\"v1\""], try fixture()), (304, [:], Data())])
        await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in "test-server-token" })
        XCTAssertNil(store.researchFailure)
        var expected = original; expected.researchDigests = store.workspace.researchDigests; expected.revision += 1
        XCTAssertEqual(store.workspace, expected); XCTAssertEqual(try store.file.load(), expected)
        let graph = store.researchCache(date: "2026-10-02")!.graph
        await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in nil })
        XCTAssertEqual(store.researchCache(date: "2026-10-02")?.graph, graph)
        XCTAssertEqual(DigestMock.state.captured().last?.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        let exported = String(data: try JSONEncoder().encode(store.workspace), encoding: .utf8)!
        XCTAssertFalse(exported.contains("test-server-token")); XCTAssertFalse(exported.contains("Authorization"))
    }
    @MainActor func testFailuresMissingAndStaleRevisionsPreserveCacheAndBackoff() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir), service = client()
        DigestMock.state.reset([(200, ["Content-Type": "application/json"], try fixture())])
        await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in nil })
        let before = store.workspace
        for reply in [(404, [:], Data()), (401, [:], Data()), (429, ["Retry-After": "120"], Data()), (200, ["Content-Type": "application/json"], try mutated { $0["summary"] = .string("Changed but revision not incremented") })] {
            DigestMock.state.reset([reply])
            await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in nil })
            XCTAssertEqual(store.workspace, before)
        }
        DigestMock.state.reset([(429, ["Retry-After": "120"], Data())])
        await store.fetchResearchDigest(date: "2026-10-01", client: service, credential: { _ in nil })
        await store.fetchResearchDigest(date: "2026-10-01", automatic: true, client: service, credential: { _ in nil })
        XCTAssertEqual(DigestMock.state.captured().count, 1)
    }
    @MainActor func testOptInReadonlyAutomaticAndConfigurationChangePreventNetworkOrLateWrites() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir), service = client()
        DigestMock.state.reset([])
        var config = store.workspace.laboratory; config.enabled = false; try store.saveLaboratoryConfiguration(config)
        await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in XCTFail("Credential accessed"); return nil })
        config.enabled = true; config.automatic = false; try store.saveLaboratoryConfiguration(config)
        await store.fetchResearchDigest(date: "2026-10-02", automatic: true, client: service, credential: { _ in XCTFail("Credential accessed"); return nil })
        let readonly = PersonalStore(previewDirectory: dir, previewWorkspace: store.workspace)
        await readonly.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in XCTFail("Credential accessed"); return nil })
        XCTAssertTrue(DigestMock.state.captured().isEmpty)
        DigestMock.state.reset([(200, ["Content-Type": "application/json"], try fixture())], delay: 0.2)
        let task = Task { await store.fetchResearchDigest(date: "2026-10-02", client: service, credential: { _ in nil }) }
        while DigestMock.state.captured().isEmpty { await Task.yield() }
        config.enabled = false; try store.saveLaboratoryConfiguration(config)
        let before = store.workspace
        await task.value
        XCTAssertEqual(store.workspace, before); XCTAssertFalse(store.researchFetching)
    }
    func testOldWorkspaceDecodesLaboratoryDisabledAndCacheEmpty() throws {
        var root = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(Workspace())).object!
        root.removeValue(forKey: "laboratory"); root.removeValue(forKey: "researchDigests")
        let workspace = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(JSONValue.object(root)))
        XCTAssertFalse(workspace.laboratory.enabled); XCTAssertTrue(workspace.researchDigests.isEmpty)
        XCTAssertNoThrow(try workspace.validated())
    }
    func testFictionalDailyPreviewAndFractionalTimestampAreValid() throws {
        let workspace = try Workspace.dailyResearchPreview()
        XCTAssertTrue(workspace.laboratory.enabled); XCTAssertFalse(workspace.laboratory.automatic)
        XCTAssertEqual(workspace.researchDigests.count, 1)
        XCTAssertNoThrow(try workspace.validated())
        let fractional = try DailyResearchDigest.decode(mutated { $0["published_at"] = .string("2026-10-02T00:00:00.123Z") })
        XCTAssertNoThrow(try fractional.materialize(language: .english))
    }
    @MainActor func testHigherRevisionRefreshPreservesOtherRecordsAndFreshCacheSkipsAutomaticRequest() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir), service = client()
        let now = Date()
        DigestMock.state.reset([(200, ["Content-Type": "application/json"], try fixture()), (200, ["Content-Type": "application/json", "ETag": "\"v2\""], try mutated { $0["revision"] = .number(2); $0["summary"] = .string("Revised fictional interpretation; not scientific evidence.") })])
        await store.fetchResearchDigest(date: "2026-10-02", now: now, client: service, credential: { _ in nil })
        await store.fetchResearchDigest(date: "2026-10-02", automatic: true, now: now.addingTimeInterval(60), client: service, credential: { _ in XCTFail("Fresh cache should skip key lookup"); return nil })
        XCTAssertEqual(DigestMock.state.captured().count, 1)
        await store.fetchResearchDigest(date: "2026-10-02", now: now, client: service, credential: { _ in nil })
        XCTAssertEqual(store.researchCache(date: "2026-10-02")?.digest.revision, 2)
        XCTAssertEqual(store.workspace.researchDigests.count, 1); XCTAssertNil(store.researchFailure)
    }
    func testUnknownLengthOversizedStreamIsRejectedAndRedirectDelegateRefusesForwarding() async throws {
        let service = client()
        DigestMock.state.reset([(200, ["Content-Type": "application/json"], Data(repeating: 32, count: DailyResearchDigest.maximumBytes + 1))])
        do { _ = try await service.fetch(configuration: configuration(), date: "2026-10-02", language: .english, token: nil, etag: nil); XCTFail("Oversized stream accepted") }
        catch { XCTAssertTrue(error is ResearchDigestNetworkError) }
        let request = URLRequest(url: URL(string: "https://other.example.org")!)
        let task = service.session.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [:])!
        ResearchNoRedirect().urlSession(service.session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected in
            XCTAssertNil(redirected)
        }
        task.cancel()
    }
    func testV1DoesNotAcceptLegacyNullEdgeProseOrMainlineRole() throws {
        for field in ["limitations", "role"] {
            let digest = try DailyResearchDigest.decode(mutated { root in
                var graph = root["graph"]!.object!
                let arrayKey = field == "role" ? "mainline" : "claim_links"
                var values = graph[arrayKey]!.array!, value = values[0].object!
                value[field] = .null; values[0] = .object(value); graph[arrayKey] = .array(values); root["graph"] = .object(graph)
            })
            XCTAssertThrowsError(try digest.materialize(language: .english))
        }
    }
}
