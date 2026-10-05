import Foundation
import PersonalCore

extension PersonalStore {
    var researchAutomaticIdentity: String {
        let config = workspace.laboratory
        return "\(config.enabled)|\(config.automatic)|\(config.baseURL)|\(config.feed)|\(config.timezone)|\(workspace.language)|\(readOnly)"
    }
    func saveLaboratoryConfiguration(_ configuration: LaboratoryConfiguration) throws {
        try configuration.validated()
        try commit { $0.laboratory = configuration }
        researchNextAttempt = [:]; researchFailure = nil; researchMessage = nil
    }
    func researchCache(date: String) -> CachedResearchDigest? {
        guard let key = try? ResearchDigestClient.key(configuration: workspace.laboratory, date: date, language: workspace.language) else { return nil }
        return workspace.researchDigests.first { $0.key == key }
    }
    func fetchResearchDigest(date: String, automatic: Bool = false, now: Date = Date(),
                             client: ResearchDigestClient? = nil,
                             credential: (String) throws -> String? = { try AssistantKeychain().read(account: $0) }) async {
        let config = workspace.laboratory, language = workspace.language
        guard config.enabled, !readOnly, !researchFetching, !automatic || config.automatic else { return }
        guard !config.baseURL.isEmpty else {
            if !automatic { researchFailure = assistantText("请先在设置中配置研究服务器。", "Configure the research server in Settings first.") }; return
        }
        guard let key = try? ResearchDigestClient.key(configuration: config, date: date, language: language) else { return }
        let cached = workspace.researchDigests.first { $0.key == key }
        if automatic {
            if let next = researchNextAttempt[key], next > now { return }
            if let cached, cached.checkedAt.addingTimeInterval(21600) > now { return }
        }
        researchFetching = true; researchFailure = nil
        researchMessage = assistantText("正在获取服务器研究摘要…", "Fetching the server research digest…")
        defer { researchFetching = false }
        do {
            let account = try ResearchDigestClient.tokenAccount(configuration: config, directory: file.directory)
            let token = try credential(account)
            let result = try await (client ?? ResearchDigestClient()).fetch(configuration: config, date: date, language: language, token: token, etag: cached?.etag)
            try Task.checkCancellation()
            guard workspace.laboratory == config, workspace.language == language, !readOnly else { return }
            switch result {
            case .downloaded(let digest, let graph, let etag):
                if let cached {
                    guard digest.id == cached.digest.id, digest.revision >= cached.digest.revision,
                          digest.revision != cached.digest.revision || digest == cached.digest else {
                        throw WorkspaceError.invalid("Digest identity/revision changed unexpectedly. / 摘要标识或版本冲突，原缓存保留。")
                    }
                }
                let entry = CachedResearchDigest(key: key, digest: digest,
                    graph: cached?.digest == digest ? cached!.graph : graph, etag: etag, checkedAt: now)
                try commit { workspace in
                    workspace.researchDigests.removeAll { $0.key == key }
                    workspace.researchDigests.insert(entry, at: 0)
                    workspace.researchDigests = Array(workspace.researchDigests.prefix(30))
                    while try JSONEncoder().encode(workspace.researchDigests).count > 12_000_000 {
                        workspace.researchDigests.removeLast()
                    }
                }
                researchMessage = assistantText("\(date) 研究摘要已缓存；可离线阅读。", "Research digest for \(date) cached for offline reading.")
                researchNextAttempt[key] = now.addingTimeInterval(21600)
            case .notModified:
                guard cached != nil else { throw ResearchDigestNetworkError.invalidResponse }
                try commit { workspace in
                    guard let index = workspace.researchDigests.firstIndex(where: { $0.key == key }) else { throw ResearchDigestNetworkError.invalidResponse }
                    workspace.researchDigests[index].checkedAt = now
                }
                researchMessage = assistantText("服务器确认摘要为最新版本。", "The server confirmed this digest is up to date.")
                researchNextAttempt[key] = now.addingTimeInterval(21600)
            case .notPublished(let delay):
                researchMessage = assistantText("\(date) 的摘要尚未发布，已有缓存保留。", "The digest for \(date) has not been published. Existing cache is preserved.")
                researchNextAttempt[key] = now.addingTimeInterval(delay)
            }
        } catch is CancellationError {
            researchMessage = nil
        } catch {
            guard workspace.laboratory == config, workspace.language == language else { return }
            if Task.isCancelled { researchMessage = nil; return }
            researchMessage = nil; researchFailure = error.localizedDescription
            let delay: TimeInterval
            if case ResearchDigestNetworkError.rateLimited(let retry) = error { delay = retry }
            else if case ResearchDigestNetworkError.authentication = error { delay = 21600 }
            else if case ResearchDigestNetworkError.forbidden = error { delay = 21600 }
            else { delay = 1800 }
            researchNextAttempt[key] = now.addingTimeInterval(delay)
        }
    }
}
