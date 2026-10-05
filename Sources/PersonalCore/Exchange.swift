import Foundation

public enum ProtocolExchange {
    public static func read(_ url: URL) throws -> ProtocolContent {
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw WorkspaceError.invalid("Protocol 文件超过 10 MB。") }
        let value: ProtocolContent
        if let direct = try? JSONDecoder().decode(ProtocolContent.self, from: data) { value = direct }
        else {
            struct Envelope: Decodable { var content: ProtocolContent }
            value = try JSONDecoder().decode(Envelope.self, from: data).content
        }
        try value.validated(); return value
    }
}
