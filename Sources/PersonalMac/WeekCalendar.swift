import PersonalCore
import SwiftUI

private struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let start: Date
    let end: Date
    let color: Color
    var busyID: UUID?
}

private struct PositionedEntry: Identifiable {
    let entry: CalendarEntry
    let lane: Int
    let lanes: Int
    var id: String { entry.id }
}

struct PersonalWeekCalendar: View {
    let store: PersonalStore
    let start: Date
    private let hourHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            let width = max(860, geometry.size.width)
            let dayWidth = (width - 54) / 7
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("时间").font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 54)
                        ForEach(0..<7) { offset in
                            let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
                            VStack(spacing: 5) {
                                Text(LocalDate.string(day, "EEE")).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Text(LocalDate.string(day, "d")).font(.system(size: 22, weight: .regular, design: .serif))
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? Palette.accent : Palette.ink)
                            }.frame(width: dayWidth, height: 66)
                                .background(Calendar.current.isDateInToday(day) ? Palette.accent.opacity(0.035) : .clear)
                        }
                    }.background(Palette.surface)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: 0) {
                                VStack(spacing: 0) {
                                    ForEach(0..<24) { hour in
                                        Text(String(format: "%02d:00", hour)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                                            .frame(width: 54, height: hourHeight, alignment: .top).id(hour)
                                    }
                                }.padding(.top, 5)
                                ForEach(0..<7) { offset in
                                    let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
                                    dayColumn(day: day, width: dayWidth)
                                }
                            }.frame(width: width, alignment: .leading)
                        }.frame(height: 560)
                            .onAppear { proxy.scrollTo(max(0, store.workspace.preferences.workStartMinute / 60 - 1), anchor: .top) }
                    }
                }.frame(width: width)
            }.scrollIndicators(.hidden)
        }.frame(height: 628).card()
    }

    private func dayColumn(day: Date, width: CGFloat) -> some View {
        let values = position(entries(day: day))
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24) { hour in
                    Rectangle().fill(hour * 60 < store.workspace.preferences.workStartMinute || hour * 60 >= store.workspace.preferences.workEndMinute ? Palette.sidebar.opacity(0.35) : Palette.surface)
                        .frame(height: hourHeight)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.5)).frame(height: 0.5) }
                        .overlay(alignment: .leading) { Rectangle().fill(Palette.line.opacity(0.5)).frame(width: 0.5) }
                }
            }
            ForEach(values) { value in
                let y = minute(value.entry.start, day: day) / 60 * hourHeight
                let endY = minute(value.entry.end, day: day) / 60 * hourHeight
                let laneWidth = (width - 8) / CGFloat(value.lanes)
                CalendarEventCard(store: store, entry: value.entry, height: max(4, endY - y - 1))
                    .frame(width: max(12, laneWidth - 3), height: max(4, endY - y - 1))
                    .offset(x: 4 + CGFloat(value.lane) * laneWidth, y: y)
            }
            if Calendar.current.isDateInToday(day) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 0) { Circle().fill(Palette.accent).frame(width: 5, height: 5); Rectangle().fill(Palette.accent).frame(height: 1) }
                        .offset(y: minute(context.date, day: day) / 60 * hourHeight)
                        .allowsHitTesting(false)
                }
            }
        }.frame(width: width, height: hourHeight * 24)
    }

    private func minute(_ date: Date, day: Date) -> CGFloat {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        if date <= day { return 0 }; if date >= next { return 1440 }
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return CGFloat((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + CGFloat(parts.second ?? 0) / 60
    }

    private func entries(day: Date) -> [CalendarEntry] {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let plan = store.activePlan.filter { $0.start < next && $0.end > day }.map { step in
            CalendarEntry(id: step.id.uuidString, title: step.title, subtitle: store.experimentName(step.experimentID) + " · " + (step.requiresAttention ? "本人操作" : "无人值守"), start: step.start, end: step.end, color: step.requiresAttention ? Palette.accent : Palette.success)
        }
        let busy = store.workspace.busyIntervals.filter { $0.start < next && $0.end > day }.map { item in
            CalendarEntry(id: item.id.uuidString, title: item.title, subtitle: item.instrumentID == nil ? "个人忙碌" : store.instrumentName(item.instrumentID), start: item.start, end: item.end, color: Palette.warning, busyID: item.id)
        }
        return (plan + busy).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    /// Each connected overlap group gets its own lane count, keeping unrelated events full-width.
    private func position(_ values: [CalendarEntry]) -> [PositionedEntry] {
        var result: [PositionedEntry] = []; var cluster: [(CalendarEntry, Int)] = []
        var laneEnds: [Date] = []; var clusterEnd = Date.distantPast
        func finish() {
            for (entry, lane) in cluster { result.append(PositionedEntry(entry: entry, lane: lane, lanes: max(1, laneEnds.count))) }
            cluster = []; laneEnds = []; clusterEnd = .distantPast
        }
        for entry in values {
            if entry.start >= clusterEnd { finish() }
            let lane = laneEnds.firstIndex { $0 <= entry.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(entry.end) } else { laneEnds[lane] = entry.end }
            cluster.append((entry, lane)); clusterEnd = max(clusterEnd, entry.end)
        }
        finish(); return result
    }
}

private struct CalendarEventCard: View {
    let store: PersonalStore
    let entry: CalendarEntry
    let height: CGFloat
    @State private var showDetails = false
    private var description: String { "\(entry.title) · \(LocalDate.dateTime(entry.start)) — \(LocalDate.dateTime(entry.end))" }
    var body: some View {
        Button { showDetails = true } label: { eventLabel }
            .buttonStyle(.plain).help(description)
            .accessibilityLabel(Text(description))
            .popover(isPresented: $showDetails) { details }
    }
    private var eventLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
                if height >= 23 { Text(entry.title).font(.system(size: 10, weight: .medium)).lineLimit(height >= 52 ? 2 : 1) }
                if height >= 52 { Text(LocalDate.time(entry.start) + "–" + LocalDate.time(entry.end)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 7).padding(.vertical, height >= 23 ? 5 : 0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(entry.color.opacity(0.10), in: RoundedRectangle(cornerRadius: min(5, height / 2)))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(entry.color).frame(width: 2) }
                .contentShape(Rectangle())
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
                    StatusPill(title: entry.subtitle, color: entry.color)
                    Text(entry.title).font(EditorialType.title(23))
                    Text(LocalDate.dateTime(entry.start) + " → " + LocalDate.dateTime(entry.end)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    if let id = entry.busyID { Button("移除忙碌时段", role: .destructive) { store.removeBusy(id); showDetails = false }.buttonStyle(.borderless).disabled(store.readOnly) }
        }.padding(22).frame(width: 320, alignment: .leading)
    }
}
