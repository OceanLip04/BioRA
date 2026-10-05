import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .array(let v): try c.encode(v); case .object(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var int: Int? { if case .number(let v) = self, v.isFinite, v.rounded() == v, v > Double(Int.min), v < Double(Int.max) { return Int(v) }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public static func decode(_ text: String) throws -> JSONValue {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") { let lines = value.components(separatedBy: "\n"); value = lines.dropFirst().dropLast().joined(separator: "\n") }
        return try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))
    }
    public func text() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
}
public struct ToolCall: Codable, Equatable, Sendable {
    public struct Function: Codable, Equatable, Sendable { public var name: String; public var arguments: String }
    public var id: String; public var type = "function"; public var function: Function
    public init(id: String, name: String, arguments: String) { self.id = id; function = Function(name: name, arguments: arguments) }
}
public enum WireContentPart: Codable, Sendable, Equatable {
    case text(String)
    case imageURL(String)

    var value: JSONValue {
        switch self {
        case .text(let text): .object(["type": .string("text"), "text": .string(text)])
        case .imageURL(let url): .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
        }
    }
    public init(from decoder: Decoder) throws {
        let object = try JSONValue(from: decoder)
        switch object["type"].string {
        case "text":
            guard let text = object["text"].string else { throw WorkspaceError.invalid("Image message text part is missing text.") }
            self = .text(text)
        case "image_url":
            guard let url = object["image_url"]["url"].string else { throw WorkspaceError.invalid("Image message part is missing its URL.") }
            self = .imageURL(url)
        default: throw WorkspaceError.invalid("Unsupported image message part.")
        }
    }
    public func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
public struct WireMessage: Codable, Sendable {
    public var role: String; public var content: String?; public var parts: [WireContentPart]?
    public var toolCalls: [ToolCall]?; public var toolCallID: String?
    public init(role: String, content: String?, parts: [WireContentPart]? = nil, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role; self.content = content; self.parts = parts; self.toolCalls = toolCalls; self.toolCallID = toolCallID
    }
    enum CodingKeys: String, CodingKey { case role, content, toolCalls = "tool_calls", toolCallID = "tool_call_id" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        if let text = try? c.decode(String.self, forKey: .content) { content = text; parts = nil }
        else if let decoded = try? c.decode([WireContentPart].self, forKey: .content) {
            parts = decoded
            content = decoded.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
        } else { content = nil; parts = nil }
        toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallID = try c.decodeIfPresent(String.self, forKey: .toolCallID)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        if let parts { try c.encode(parts, forKey: .content) }
        else { try c.encodeIfPresent(content, forKey: .content) }
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}
public struct ToolDefinition: Codable, Sendable {
    public struct Function: Codable, Sendable { public var name: String; public var description: String; public var parameters: JSONValue }
    public var type = "function"; public var function: Function
    public init(name: String, description: String, parameters: JSONValue) { function = Function(name: name, description: description, parameters: parameters) }
}
public struct ModelReply: Sendable {
    public var content: String; public var toolCalls: [ToolCall]; public var inputTokens: Int; public var outputTokens: Int
}
public enum ModelClient {
    public static func complete(connection: ProviderConnection, model: ModelProfile, apiKey: String?, messages: [WireMessage], tools: [ToolDefinition] = [], json: Bool = false, onDelta: (@Sendable (String) async -> Void)? = nil, using testSession: URLSession? = nil) async throws -> ModelReply {
        try connection.validated(); try model.validated(); try Task.checkCancellation()
        var payload: [String: JSONValue] = ["model": .string(model.model), "messages": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(messages))]
        payload[model.tokenParameter] = .number(Double(model.maxOutputTokens))
        if let temperature = model.temperature { payload["temperature"] = .number(temperature) }
        if !tools.isEmpty { payload["tools"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(tools)); payload["tool_choice"] = .string("auto") }
        if json && model.supportsJSON { payload["response_format"] = .object(["type": .string("json_object")]) }
        let stream = model.stream && !json
        if stream { payload["stream"] = .bool(true) }
        var request = URLRequest(url: try connection.endpoint("chat/completions"), timeoutInterval: 120)
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let session = testSession ?? URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { if testSession == nil { session.invalidateAndCancel() } }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw WorkspaceError.invalid("模型服务没有有效 HTTP 响应。") }
            if !stream || !(http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") || !(200..<300).contains(http.statusCode) {
                var data = Data()
                for try await byte in bytes { guard data.count < 4 * 1024 * 1024 else { throw WorkspaceError.invalid("模型响应超过 4 MB。") }; data.append(byte) }
                try Task.checkCancellation(); try checkStatus(http.statusCode, data: data, key: apiKey)
                let root = try JSONDecoder().decode(JSONValue.self, from: data)
                guard let choice = root["choices"].array?.first else { throw WorkspaceError.invalid("无法识别模型响应，请检查兼容接口。") }
                if choice["finish_reason"].string == "length" { throw WorkspaceError.invalid("输出达到 Token 上限，请提高模型最大输出 Token 或缩短任务。") }
                let message = choice["message"]
                let calls = try parseCalls(message["tool_calls"])
                let content = message["content"].string ?? ""
                guard !content.isEmpty || !calls.isEmpty else { throw WorkspaceError.invalid("模型返回空内容。") }
                return ModelReply(content: content, toolCalls: calls, inputTokens: root["usage"]["prompt_tokens"].int ?? 0, outputTokens: root["usage"]["completion_tokens"].int ?? 0)
            }
            var content = ""; var calls: [Int: ToolCall] = [:]; var total = 0; var sawDone = false; var finished = false
            for try await line in bytes.lines {
                try Task.checkCancellation(); total += line.utf8.count
                guard total <= 4 * 1024 * 1024 else { throw WorkspaceError.invalid("模型响应超过 4 MB。") }
                guard line.hasPrefix("data:") else { continue }
                let text = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if text == "[DONE]" { sawDone = true; break }
                let root = try JSONValue.decode(text)
                if let error = root["error"]["message"].string { throw WorkspaceError.invalid(String(error.prefix(500)).replacingOccurrences(of: apiKey ?? "\u{0}", with: "[Key]")) }
                guard let choice = root["choices"].array?.first else { continue }
                if choice["finish_reason"].string == "length" { throw WorkspaceError.invalid("输出达到 Token 上限，请调整模型参数后重试。") }
                if choice["finish_reason"].string != nil { finished = true }
                let delta = choice["delta"]
                if let piece = delta["content"].string { content += piece; await onDelta?(content) }
                for part in delta["tool_calls"].array ?? [] {
                    let i = part["index"].int ?? 0
                    var call = calls[i] ?? ToolCall(id: "", name: "", arguments: "")
                    if let id = part["id"].string { call.id += id }
                    call.function.name += part["function"]["name"].string ?? ""
                    call.function.arguments += part["function"]["arguments"].string ?? ""
                    calls[i] = call
                }
            }
            guard sawDone || finished else { throw WorkspaceError.invalid("模型连接中断，未执行不完整的输出。") }
            let values = calls.keys.sorted().compactMap { calls[$0] }
            guard !content.isEmpty || !values.isEmpty, values.allSatisfy({ !$0.id.isEmpty && !$0.function.name.isEmpty }) else { throw WorkspaceError.invalid("模型返回空内容或不完整的工具调用。") }
            return ModelReply(content: content, toolCalls: values, inputTokens: 0, outputTokens: 0)
        } catch { if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }; throw error }
    }
    public static func discover(connection: ProviderConnection, apiKey: String?) async throws -> [String] {
        var request = URLRequest(url: try connection.endpoint("models"), timeoutInterval: 30)
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil); defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard data.count < 4 * 1024 * 1024, let response = response as? HTTPURLResponse else { throw WorkspaceError.invalid("模型目录响应无效。") }
        try checkStatus(response.statusCode, data: data, key: apiKey)
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let values = root["data"].array else { throw WorkspaceError.invalid("该接口不提供兼容模型列表，可手动添加模型。") }
        return Array(Set(values.compactMap { $0["id"].string })).sorted()
    }
    private static func parseCalls(_ value: JSONValue) throws -> [ToolCall] {
        guard value != .null else { return [] }; return try JSONDecoder().decode([ToolCall].self, from: JSONEncoder().encode(value))
    }
    private static func checkStatus(_ status: Int, data: Data, key: String?) throws {
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw WorkspaceError.invalid("模型连接认证失败（HTTP \(status)），请检查 API Key 和地址。") }
            let root = try? JSONDecoder().decode(JSONValue.self, from: data)
            var detail = root?["error"]["message"].string ?? "请检查服务地址、模型名称和可用额度。"
            if let key, !key.isEmpty { detail = detail.replacingOccurrences(of: key, with: "[Key]") }
            throw WorkspaceError.invalid("模型服务 HTTP \(status)：\(String(detail.prefix(700)))")
        }
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
