import Foundation
import XCTest
@testable import PersonalCore

final class PersonalCoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return value
    }
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 28) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    func testDemoIsExplicitAndValid() throws {
        let workspace = Workspace.demo(now: date(8), calendar: calendar)
        XCTAssertTrue(workspace.isDemo)
        try workspace.validated()
        XCTAssertEqual(workspace.instruments.count, 3)
        XCTAssertEqual(workspace.plan.count, 11)
        XCTAssertFalse(Workspace().isDemo)
    }
    func testScheduleAvoidsPersonalConflicts() throws {
        var workspace = Workspace()
        let procedure = Procedure(name: "测量", steps: [ProcedureStep(title: "测量", minutes: 30)])
        let first = Experiment(name: "先安排", procedureID: procedure.id)
        workspace.experiments = [first]
        workspace.plan = [PlannedStep(experimentID: first.id, title: "已有安排", instrumentID: nil, start: date(9), end: date(10))]
        let second = Experiment(name: "后安排", procedureID: procedure.id)
        let result = try Planner.schedule(experiment: second, procedure: procedure, in: workspace, starting: date(9, 15), calendar: calendar)
        XCTAssertEqual(result.first?.start, date(10))
        XCTAssertEqual(result.first?.end, date(10, 30))
    }
    func testCancelledPlansReleaseTime() throws {
        var workspace = Workspace()
        let procedure = Procedure(name: "测量", steps: [ProcedureStep(title: "测量", minutes: 30)])
        var cancelled = Experiment(name: "取消", procedureID: procedure.id); cancelled.status = .cancelled
        workspace.experiments = [cancelled]
        workspace.plan = [PlannedStep(experimentID: cancelled.id, title: "旧安排", instrumentID: nil, start: date(9), end: date(10))]
        let result = try Planner.schedule(experiment: Experiment(name: "新安排", procedureID: procedure.id), procedure: procedure, in: workspace, starting: date(9), calendar: calendar)
        XCTAssertEqual(result.first?.start, date(9))
    }
    func testWorkdayOverflowMovesWholeStepToTomorrow() throws {
        let procedure = Procedure(name: "长步骤", steps: [ProcedureStep(title: "处理", minutes: 90)])
        let result = try Planner.schedule(experiment: Experiment(name: "新实验", procedureID: procedure.id), procedure: procedure, in: Workspace(), starting: date(17), calendar: calendar)
        XCTAssertEqual(result.first?.start, date(9, day: 29))
        XCTAssertEqual(result.first?.end, date(10, 30, day: 29))
    }
    func testUnavailableAndOversizedStepsAreRejected() throws {
        var workspace = Workspace()
        let instrument = Instrument(name: "不可用仪器", available: false); workspace.instruments = [instrument]
        let procedure = Procedure(name: "测量", steps: [ProcedureStep(title: "测量", minutes: 30, instrumentID: instrument.id)])
        XCTAssertThrowsError(try Planner.schedule(experiment: Experiment(name: "测试", procedureID: procedure.id), procedure: procedure, in: workspace, starting: date(9), calendar: calendar))
        let oversized = Procedure(name: "过长", steps: [ProcedureStep(title: "处理", minutes: 541)])
        XCTAssertThrowsError(try Planner.schedule(experiment: Experiment(name: "测试", procedureID: oversized.id), procedure: oversized, in: workspace, starting: date(9), calendar: calendar))
    }
    func testPersistenceRoundTripAndInvalidSavePreservesOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("personal-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WorkspaceFile(directory: directory)
        let workspace = Workspace.demo(now: date(8), calendar: calendar)
        try file.save(workspace)
        XCTAssertEqual(try file.load(), workspace)
        let original = try Data(contentsOf: file.url)
        var invalid = workspace; invalid.instruments.removeAll()
        XCTAssertThrowsError(try file.save(invalid))
        XCTAssertEqual(try Data(contentsOf: file.url), original)
    }
    func testCorruptFileIsNeverSilentlyReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("personal-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = WorkspaceFile(directory: directory)
        let invalid = Data("not-json".utf8); try invalid.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url), invalid)
    }
}
