import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var title: String {
        switch self {
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    public var localeIdentifier: String { rawValue }

    public var responseRule: String {
        switch self {
        case .chinese:
            "所有面向用户的新生成文字均使用简体中文；JSON 键、固定枚举、UUID、单位符号和用户原始资料保持原样。"
        case .english:
            "Write every newly generated user-facing string in English, even when the user's message, conversation history, attachments, or stored workspace data are in Chinese. Translate names, explanations, clarifying questions, proposed experiment titles, and all Protocol document text into natural scientific English. Preserve exact JSON keys, enum values, UUIDs, units, identifiers, and quoted source material that must be passed to another stage. Do not translate existing source data in place."
        }
    }

    public static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }

    public func requiresEnglish(_ value: String?) throws {
        guard self != .english || !Self.containsHan(value ?? "") else {
            throw WorkspaceError.invalid("The generated text must be in English. Translate Chinese prose while preserving IDs, enum values, and source material.")
        }
    }
}
