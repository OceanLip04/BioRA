import Foundation
import XCTest
@testable import PersonalCore

final class SchedulingAuditTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: hour, minute: minute, second: second))!
    }
    private func procedure(_ steps: [ProtocolStep]) -> Procedure {
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "Preparation", subblocks: [ProtocolSubblock(title: "Actions", steps: steps)])])
        content.renumber()
        return Procedure(name: "Scheduling audit", content: content, status: .published)
    }
    private func plan(_ p: Procedure, _ workspace: Workspace = Workspace(), start: Date? = nil, preferences: SchedulePreferences = SchedulePreferences()) throws -> [PlannedStep] {
        try Planner.schedule(experiment: Experiment(name: "Audit", procedureID: p.id), procedure: p, in: workspace,
            starting: start ?? date(9), calendar: calendar, preferences: preferences)
    }

    func testAllRequiredInstrumentsMustBeFreeTogether() throws {
        let a = Instrument(name: "Centrifuge"), b = Instrument(name: "Detector")
        var step = ProtocolStep(title: "Measure", minutes: 30, instrumentID: a.id)
        step.equipmentNeeded = [b.name]
        var workspace = Workspace(); workspace.instruments = [a, b]
        workspace.busyIntervals = [BusyInterval(title: "A occupied", start: date(9), end: date(10), instrumentID: a.id),
            BusyInterval(title: "B occupied", start: date(9, 30), end: date(11), instrumentID: b.id)]
        let result = try plan(procedure([step]), workspace)
        XCTAssertEqual(result.first?.start, date(11))
        XCTAssertEqual(result.first?.resources, Set([a.id, b.id]))
    }

    func testUnattendedWorkReleasesPersonButNotItsInstrument() throws {
        let a = Instrument(name: "Incubator"), b = Instrument(name: "Detector")
        var workspace = Workspace(); workspace.instruments = [a, b]
        let existing = Experiment(name: "Incubation", procedureID: UUID())
        workspace.experiments = [existing]
        var occupied = PlannedStep(experimentID: existing.id, title: "Incubate", instrumentID: a.id, start: date(9), end: date(12))
        occupied.requiresAttention = false; workspace.plan = [occupied]
        XCTAssertEqual(try plan(procedure([ProtocolStep(title: "Read", minutes: 30, instrumentID: b.id)]), workspace).first?.start, date(9))
        XCTAssertEqual(try plan(procedure([ProtocolStep(title: "Load", minutes: 30, instrumentID: a.id)]), workspace).first?.start, date(12))
    }

    func testAmbiguousEquipmentNameIsRejected() throws {
        var workspace = Workspace(); workspace.instruments = [Instrument(name: "Reader"), Instrument(name: "reader")]
        var step = ProtocolStep(title: "Measure", minutes: 30); step.equipmentNeeded = [" Reader "]
        XCTAssertThrowsError(try plan(procedure([step]), workspace))
    }

    func testTouchingBusyBoundaryDoesNotCountAsConflictAndStartRoundsUp() throws {
        var workspace = Workspace()
        workspace.busyIntervals = [BusyInterval(title: "Before", start: date(8), end: date(9)),
            BusyInterval(title: "After", start: date(9, 30), end: date(10))]
        let p = procedure([ProtocolStep(title: "Measure", minutes: 30)])
        XCTAssertEqual(try plan(p, workspace).first?.start, date(9))
        XCTAssertEqual(try plan(p, start: date(9, 0, 30)).first?.start, date(9, 1))
    }

    func testRestBreakSplitsOnlyPausableWorkAndPreservesFullDuration() throws {
        var step = ProtocolStep(title: "Sort samples", minutes: 90); step.canPause = true
        var preferences = SchedulePreferences(); preferences.breakEveryMinutes = 30; preferences.breakMinutes = 10
        let result = try plan(procedure([step]), preferences: preferences)
        XCTAssertEqual(result.map(\.minutes), [30, 30, 30])
        XCTAssertEqual(result.map(\.start), [date(9), date(9, 40), date(10, 20)])
        XCTAssertEqual(result.last?.end, date(10, 50))
    }

    func testMidnightClosingKeepsEveryMinuteWhenSplittingAcrossDays() throws {
        var step = ProtocolStep(title: "Pause-safe work", minutes: 120); step.canPause = true
        var preferences = SchedulePreferences(); preferences.workStartMinute = 0; preferences.workEndMinute = 1440
        let result = try plan(procedure([step]), start: date(23), preferences: preferences)
        XCTAssertEqual(result.map(\.minutes), [60, 60])
        XCTAssertEqual(result[0].end, result[1].start)
        XCTAssertEqual(result.last?.end.timeIntervalSince(date(23)), 7200)
    }

    func testSeededTwoHundredConflictScenariosKeepDurationsAndAvoidBusyTime() throws {
        var seed: UInt64 = 20261002
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(bound))
        }
        for scenario in 0..<200 {
            let instrument = Instrument(name: "Reader")
            var workspace = Workspace(); workspace.instruments = [instrument]
            workspace.busyIntervals = (0..<6).map { index in
                let begin = date(9).addingTimeInterval(Double(next(420) * 60))
                return BusyInterval(title: "Busy \(index)", start: begin, end: begin.addingTimeInterval(Double((15 + next(90)) * 60)),
                    instrumentID: next(2) == 0 ? nil : instrument.id)
            }
            let steps = (0..<3).map { index in
                var step = ProtocolStep(title: "Action \(index)", minutes: 10 + next(110), instrumentID: instrument.id)
                step.canPause = next(2) == 0
                return step
            }
            let p = procedure(steps), result = try plan(p, workspace)
            XCTAssertEqual(result.map(\.minutes).reduce(0, +), steps.map(\.durationMinutes).reduce(0, +), "Scenario \(scenario)")
            for (index, segment) in result.enumerated() {
                if index > 0 { XCTAssertGreaterThanOrEqual(segment.start, result[index - 1].end, "Scenario \(scenario)") }
                for busy in workspace.busyIntervals {
                    XCTAssertFalse(segment.start < busy.end && segment.end > busy.start, "Scenario \(scenario) overlaps \(busy.title)")
                }
                XCTAssertEqual(segment.resources, Set([instrument.id]))
            }
            for step in p.currentVersion.content.atomicSteps {
                let pieces = result.filter { $0.stepID == step.id }
                XCTAssertEqual(pieces.map(\.minutes).reduce(0, +), step.durationMinutes)
                if !step.canPause { XCTAssertEqual(pieces.count, 1) }
            }
        }
    }
}
