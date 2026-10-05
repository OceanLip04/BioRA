import Foundation

/// Deliberately rejects recurrence instead of silently losing future busy times.
public enum CalendarExchange {
    public static func read(_ url: URL, calendar: Calendar = .current) throws -> [BusyInterval] {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw WorkspaceError.invalid("日历文件最多 10 MB。") }
        return try parse(String(contentsOf: url, encoding: .utf8), calendar: calendar)
    }
    public static func parse(_ source: String, calendar: Calendar = .current) throws -> [BusyInterval] {
        let physical = source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines: [String] = []
        for line in physical { if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += line.dropFirst() } else { lines.append(line) } }
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else { throw WorkspaceError.invalid("不是有效的 ICS 日历。") }
        var active = false; var entries: [(String, String)] = []; var result: [BusyInterval] = []
        func date(_ key: String, _ value: String) throws -> Date {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.isLenient = false
            formatter.timeZone = calendar.timeZone
            if let tz = key.components(separatedBy: ";").first(where: { $0.hasPrefix("TZID=") }) {
                let id = String(tz.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let zone = TimeZone(identifier: id) else { throw WorkspaceError.invalid("不支持的日历时区：\(id)。") }; formatter.timeZone = zone
            }
            if key.contains("VALUE=DATE") { formatter.dateFormat = "yyyyMMdd" }
            else if value.hasSuffix("Z") { formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'" }
            else { formatter.dateFormat = "yyyyMMdd'T'HHmmss" }
            guard let parsed = formatter.date(from: value) else { throw WorkspaceError.invalid("无法读取日历时间：\(value)。") }; return parsed
        }
        func decode(_ value: String) -> String { value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\") }
        for line in lines {
            if line == "BEGIN:VEVENT" { guard !active else { throw WorkspaceError.invalid("日历事件嵌套无效。") }; active = true; entries = []; continue }
            if line == "END:VEVENT" {
                guard active else { throw WorkspaceError.invalid("日历事件缺少起始标记。") }; active = false
                if entries.contains(where: { $0.0 == "STATUS" && $0.1 == "CANCELLED" }) || entries.contains(where: { $0.0 == "TRANSP" && $0.1 == "TRANSPARENT" }) { continue }
                guard !entries.contains(where: { ["RRULE", "RDATE", "EXDATE", "RECURRENCE-ID"].contains($0.0.components(separatedBy: ";")[0]) }) else { throw WorkspaceError.invalid("包含重复事件；请从日历导出展开后的独立事件。本轮没有导入任何记录。") }
                guard let startEntry = entries.first(where: { $0.0.components(separatedBy: ";")[0] == "DTSTART" }) else { throw WorkspaceError.invalid("日历事件缺少开始时间。") }
                let start = try date(startEntry.0, startEntry.1)
                let end: Date
                if let e = entries.first(where: { $0.0.components(separatedBy: ";")[0] == "DTEND" }) { end = try date(e.0, e.1) }
                else if startEntry.0.contains("VALUE=DATE"), let next = calendar.date(byAdding: .day, value: 1, to: start) { end = next }
                else { throw WorkspaceError.invalid("日历事件缺少结束时间；暂不支持 DURATION。") }
                guard end > start else { throw WorkspaceError.invalid("日历事件结束时间必须晚于开始时间。") }
                result.append(BusyInterval(title: decode(entries.first(where: { $0.0 == "SUMMARY" })?.1 ?? "日历忙碌"), start: start, end: end))
                guard result.count <= 10000 else { throw WorkspaceError.invalid("日历事件过多。") }; continue
            }
            if active, let colon = line.firstIndex(of: ":") { entries.append((String(line[..<colon]).uppercased(), String(line[line.index(after: colon)...]))) }
        }
        guard !active else { throw WorkspaceError.invalid("日历事件不完整。") }; return result
    }
    public static func export(_ steps: [PlannedStep]) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,") }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//LabMonitor//Personal//ZH", "CALSCALE:GREGORIAN"]
        for step in steps {
            lines += ["BEGIN:VEVENT", "UID:\(step.id.uuidString)@labmonitor.personal", "DTSTAMP:" + formatter.string(from: Date()), "DTSTART:" + formatter.string(from: step.start), "DTEND:" + formatter.string(from: step.end), "SUMMARY:" + escape(step.title), "DESCRIPTION:本机计划，不代表真实仪器预约", "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        // Fold at 75 UTF-8 octets without splitting a Unicode scalar.
        return lines.map { line in
            var segments: [String] = []; var segment = ""; var bytes = 0
            for scalar in line.unicodeScalars { let size = String(scalar).utf8.count; if bytes + size > 75 { segments.append(segment); segment = " "; bytes = 1 }; segment.unicodeScalars.append(scalar); bytes += size }
            segments.append(segment); return segments.joined(separator: "\r\n")
        }.joined(separator: "\r\n") + "\r\n"
    }
}
