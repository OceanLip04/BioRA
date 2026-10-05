import CryptoKit
import Foundation
import PersonalCore

enum ResearchDigestFetch: Sendable {
    case downloaded(DailyResearchDigest, ScientificQuestion, String?)
    case notModified
    case notPublished(TimeInterval)
}

enum ResearchDigestNetworkError: LocalizedError {
    case authentication, forbidden, rateLimited(TimeInterval), server, invalidResponse, tooLarge, redirect
    var errorDescription: String? {
        switch self {
        case .authentication: "Server token is missing or expired (401). / 服务器令牌缺失或已过期（401）。"
        case .forbidden: "This token cannot access the feed (403). / 此令牌无权访问频道（403）。"
        case .rateLimited: "Server rate limit reached (429). Try later. / 服务器限流（429），请稍后重试。"
        case .server: "The research server is unavailable. Cached summaries are preserved. / 研究服务器暂不可用，缓存摘要已保留。"
        case .invalidResponse: "Invalid research response, MIME type, date, language or version. / 研究响应、内容类型、日期、语言或版本无效。"
        case .tooLarge: "Research response exceeds 2 MB. / 研究响应超过 2 MB。"
        case .redirect: "Server redirects are not followed. Configure the final HTTPS base URL. / 不跟随服务器重定向，请配置最终 HTTPS 地址。"
        }
    }
}

/// Never forward Authorization across redirects, including redirects on the same host.
final class ResearchNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ResearchDigestClient: Sendable {
    let session: URLSession
    private let ownsSession: Bool
    init(session: URLSession? = nil) {
        ownsSession = session == nil
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
            config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }
    static func key(configuration: LaboratoryConfiguration, date: String, language: AppLanguage) throws -> String {
        let identity = try [configuration.serverURL().absoluteString, configuration.feed, configuration.timezone,
                            language == .english ? "en" : "zh-Hans", date].joined(separator: "\n")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func tokenAccount(configuration: LaboratoryConfiguration, directory: URL) throws -> String {
        let identity = try configuration.serverURL().absoluteString + "\n" + configuration.feed + "\n" + directory.standardizedFileURL.path
        return "biora.research." + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func request(configuration: LaboratoryConfiguration, date: String, language: AppLanguage,
                        token: String?, etag: String?) throws -> URLRequest {
        try configuration.validated()
        guard configuration.enabled, LaboratoryConfiguration.validDay(date) else {
            throw WorkspaceError.invalid("Laboratory is disabled or the requested date is invalid. / 实验室已关闭或日期无效。")
        }
        let endpoint = try configuration.serverURL().appendingPathComponent("v1/research/daily")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "date", value: date), URLQueryItem(name: "timezone", value: configuration.timezone),
                                 URLQueryItem(name: "language", value: language == .english ? "en" : "zh-Hans"), URLQueryItem(name: "feed", value: configuration.feed)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language == .english ? "en" : "zh-Hans", forHTTPHeaderField: "Accept-Language")
        request.setValue("BioRA/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.15.0"), forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            guard token.utf8.count <= 4096, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                throw WorkspaceError.invalid("Invalid bearer token. / 访问令牌格式无效。")
            }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let etag {
            guard etag.utf8.count <= 512, !etag.contains("\r"), !etag.contains("\n") else { throw ResearchDigestNetworkError.invalidResponse }
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }
    static func retryDelay(_ response: HTTPURLResponse, fallback: TimeInterval) -> TimeInterval {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(raw), seconds.isFinite else { return fallback }
        return min(86400, max(60, seconds))
    }
    func fetch(configuration: LaboratoryConfiguration, date: String, language: AppLanguage, token: String?, etag: String?) async throws -> ResearchDigestFetch {
        defer { if ownsSession { session.finishTasksAndInvalidate() } }
        let request = try Self.request(configuration: configuration, date: date, language: language, token: token, etag: etag)
        let delegate = ResearchNoRedirect()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw ResearchDigestNetworkError.invalidResponse }
        switch http.statusCode {
        case 304:
            guard etag != nil else { throw ResearchDigestNetworkError.invalidResponse }; return .notModified
        case 204, 404: return .notPublished(Self.retryDelay(http, fallback: 1800))
        case 202: return .notPublished(Self.retryDelay(http, fallback: 900))
        case 401: throw ResearchDigestNetworkError.authentication
        case 403: throw ResearchDigestNetworkError.forbidden
        case 429: throw ResearchDigestNetworkError.rateLimited(Self.retryDelay(http, fallback: 3600))
        case 300...399: throw ResearchDigestNetworkError.redirect
        case 200: break
        default: throw ResearchDigestNetworkError.server
        }
        guard http.mimeType?.lowercased() == "application/json" else { throw ResearchDigestNetworkError.invalidResponse }
        guard response.expectedContentLength <= DailyResearchDigest.maximumBytes else { throw ResearchDigestNetworkError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < DailyResearchDigest.maximumBytes else { throw ResearchDigestNetworkError.tooLarge }
            data.append(byte)
            if data.count % 4096 == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        let rawETag = http.value(forHTTPHeaderField: "ETag")
        guard rawETag.map({ $0.utf8.count <= 512 && !$0.contains("\r") && !$0.contains("\n") }) ?? true else { throw ResearchDigestNetworkError.invalidResponse }
        return try await Task.detached(priority: .utility) {
            let digest = try DailyResearchDigest.decode(data)
            guard digest.date == date, digest.feed == configuration.feed, digest.timezone == configuration.timezone,
                  digest.language == (language == .english ? "en" : "zh-Hans") else { throw ResearchDigestNetworkError.invalidResponse }
            let graph = try digest.materialize(language: language)
            return .downloaded(digest, graph, rawETag)
        }.value
    }
}
