import AppKit
import Observation
import PersonalCore
import SwiftUI

/// A small, shared visual vocabulary for the personal workspace.
@MainActor @Observable final class ThemeAppearance {
    static let shared = ThemeAppearance()
    var theme: AppTheme = .paper
}

@MainActor enum Palette {
    private static var paper: Bool { ThemeAppearance.shared.theme == .paper }
    static var ink: Color { paper ? Color(red: 0.18, green: 0.17, blue: 0.15) : Color(nsColor: .labelColor) }
    static var muted: Color { paper ? Color(red: 0.46, green: 0.44, blue: 0.40) : Color(nsColor: .secondaryLabelColor) }
    static var accent: Color { paper ? Color(red: 0.69, green: 0.36, blue: 0.25) : Color.accentColor }
    static var green: Color { accent }
    static var success: Color { paper ? Color(red: 0.33, green: 0.43, blue: 0.34) : Color(nsColor: .systemGreen) }
    static var canvas: Color { paper ? Color(red: 0.975, green: 0.967, blue: 0.947) : Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { paper ? Color(red: 0.998, green: 0.994, blue: 0.983) : Color(nsColor: .controlBackgroundColor) }
    static var sidebar: Color { paper ? Color(red: 0.937, green: 0.925, blue: 0.897) : Color(nsColor: .underPageBackgroundColor) }
    static var line: Color { paper ? Color(red: 0.86, green: 0.84, blue: 0.80) : Color(nsColor: .separatorColor) }
    static var selection: Color { paper ? Color(red: 0.89, green: 0.87, blue: 0.83) : Color.accentColor.opacity(0.12) }
    static var warning: Color { paper ? Color(red: 0.60, green: 0.40, blue: 0.16) : Color(nsColor: .systemOrange) }
}

@MainActor enum EditorialType {
    static func title(_ size: CGFloat = 32) -> Font {
        ThemeAppearance.shared.theme == .paper ? .custom("Songti SC", size: size) : .system(size: min(size, 28), weight: .semibold)
    }
}

struct BrandMark: View {
    var size: CGFloat = 32
    private var image: NSImage? {
        Bundle.main.url(forResource: "BioRAIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high) }
            else { Image(systemName: "flask").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(Palette.accent) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? (ThemeAppearance.shared.theme == .paper ? Palette.ink : Palette.accent) : Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent ? Palette.accent : Palette.line, lineWidth: 0.7))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).tracking(1.4).foregroundStyle(Palette.muted) }
}

struct StatusPill: View {
    let title: String
    var color: Color = Palette.success
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 4, height: 4); Text(title) }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.07), in: Capsule())
    }
}

enum LocalDate {
    static func string(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func time(_ date: Date) -> String { string(date, "HH:mm") }
    static func dateTime(_ date: Date) -> String { string(date, "M月d日 HH:mm") }
}
