public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case paper, macOS = "macos"
    public func title(_ language: AppLanguage) -> String {
        switch self {
        case .paper: language == .english ? "Paper · Warm & Editorial" : "纸感 · 暖色编辑风"
        case .macOS: language == .english ? "macOS · Native" : "macOS · 原生风格"
        }
    }
}
