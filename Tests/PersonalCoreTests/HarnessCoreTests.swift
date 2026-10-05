import Foundation
import XCTest
@testable import PersonalCore

final class HarnessCoreTests: XCTestCase {
    func testFixedIntentDictionaryRejectsUnknownAndCoversWorkspaceFunctions() throws {
        XCTAssertEqual(AssistantIntent.allCases.count, 18)
        for intent in AssistantIntent.allCases {
            XCTAssertEqual(try AssistantIntent.parseLabel(" \n" + intent.rawValue + "\n"), intent)
            XCTAssertTrue(IntentPrompts.classifier(.english).contains(intent.rawValue))
            XCTAssertTrue(IntentPrompts.classifier(.chinese).contains(intent.rawValue))
        }
        for invalid in ["tools", "schedule question_answer", "\"schedule\"", "{\"user_intent\":\"schedule\"}", "schedule\nBecause it is a schedule"] {
            XCTAssertThrowsError(try AssistantIntent.parseLabel(invalid))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(IntentDecision.self, from: Data("{\"user_intent\":\"tools\",\"reason\":\"随意\"}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(IntentDecision.self, from: Data("{\"user_intent\":\"schedule\"}".utf8)))
    }
    func testMinimizeFragmentationRanksDelayedWholeWorkdayFirst() throws {
        var step = ProtocolStep(title: "可暂停操作", minutes: 120); step.canPause = true
        let p = Procedure(name: "分段", content: tree(step), status: .published)
        let ranked = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, objective: .minimizeFragmentation)
        XCTAssertGreaterThan(ranked.count, 1); XCTAssertEqual(ranked[0].steps.count, 1); XCTAssertEqual(ranked[0].steps.first?.start, date(9, day: 29))
        for candidate in ranked { try Planner.validateCandidate(candidate, procedure: p, workspace: Workspace(), calendar: calendar) }
    }
    func testEarliestFinishRanksBaselineInsteadOfLessFragmentedLaterPlan() throws {
        var step = ProtocolStep(title: "可暂停操作", minutes: 120); step.canPause = true
        let p = Procedure(name: "分段", content: tree(step), status: .published)
        let candidates = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, objective: .earliestFinish)
        XCTAssertEqual(candidates[0].steps.first?.start, date(17)); XCTAssertEqual(candidates[0].steps.last?.end, date(10, day: 29))
    }
    func testAvoidOvernightSoftObjectivePrefersAllWorkingHoursEvenBeforeMidnight() throws {
        var step = ProtocolStep(title: "孵育", minutes: 300); step.canPause = true; step.unattended = true; step.overnightSafe = true
        let p = Procedure(name: "孵育", content: tree(step), status: .published)
        let earliest = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, objective: .earliestFinish)
        let avoiding = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, objective: .avoidOvernight)
        XCTAssertEqual(earliest[0].steps.last?.end, date(22)); XCTAssertFalse(avoiding[0].preferences.allowOvernight)
        XCTAssertEqual(avoiding[0].steps.last?.end, date(13, day: 29))
    }
    func testHardDeadlineFiltersSoftObjectiveAndImpossibleDeadlinesFail() throws {
        var step = ProtocolStep(title: "可暂停操作", minutes: 120); step.canPause = true
        let p = Procedure(name: "分段", content: tree(step), status: .published)
        let candidates = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, objective: .minimizeFragmentation, latestFinish: date(10, day: 29))
        XCTAssertEqual(candidates.count, 1); XCTAssertEqual(candidates[0].steps.count, 2)
        XCTAssertThrowsError(try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(17), preferences: SchedulePreferences(), calendar: calendar, latestFinish: date(18)))
    }
    func testAdditionalBusyConstraintsPersistAndAreRecheckedWhenAdopting() throws {
        let p = Procedure(name: "测量", content: tree(ProtocolStep(title: "操作", minutes: 60)), status: .published)
        let busy = BusyInterval(title: "临时会议", start: date(9), end: date(10))
        let candidate = try Planner.candidates(name: "实验", procedure: p, workspace: Workspace(), starting: date(9), preferences: SchedulePreferences(), calendar: calendar, additionalBusyIntervals: [busy])[0]
        XCTAssertEqual(candidate.steps.first?.start, date(10)); XCTAssertEqual(candidate.additionalBusyIntervals, [busy])
        try Planner.validateCandidate(candidate, procedure: p, workspace: Workspace(), calendar: calendar)
        var tampered = candidate; tampered.steps[0].start = date(9); tampered.steps[0].end = date(10)
        XCTAssertThrowsError(try Planner.validateCandidate(tampered, procedure: p, workspace: Workspace(), calendar: calendar))
        tampered = candidate; tampered.latestFinish = date(10)
        XCTAssertThrowsError(try Planner.validateCandidate(tampered, procedure: p, workspace: Workspace(), calendar: calendar))
    }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private func date(_ hour: Int, day: Int = 28) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }
    private func tree(_ step: ProtocolStep) -> ProtocolContent { var c = ProtocolContent(blocks: [ProtocolBlock(title: "阶段", subblocks: [ProtocolSubblock(title: "分组", steps: [step])])]); c.renumber(); return c }
    func testNestedLoopsAndV3RoundTrip() throws {
        var c = tree(ProtocolStep(title: "重复测量", minutes: 10))
        c.blocks[0].kind = "loop"; c.blocks[0].loop = ProtocolLoop()
        c.blocks[0].subblocks[0].kind = "loop"; var loop = ProtocolLoop(); loop.count = 3; c.blocks[0].subblocks[0].loop = loop
        let decoded = try JSONDecoder().decode(ProtocolContent.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c); XCTAssertEqual(try decoded.executionItems().count, 6)
        XCTAssertEqual(try decoded.executionItems().last?.iteration, "2.3")
        let p = Procedure(name: "循环", content: c, status: .published)
        let plan = try Planner.schedule(experiment: Experiment(name: "实验", procedureID: p.id), procedure: p, in: Workspace(), starting: date(9), calendar: calendar)
        XCTAssertEqual(plan.count, 6); XCTAssertEqual(plan.map(\.minutes).reduce(0, +), 60)
    }
    func testCrossGroupMovesPreserveStepFieldsAndIDs() throws {
        var step = ProtocolStep(title: "操作", minutes: 30); step.notes = "完整备注"; step.reagents = ["试剂 A"]
        var c = ProtocolContent(blocks: [ProtocolBlock(title: "一", subblocks: [ProtocolSubblock(title: "甲", steps: [step, ProtocolStep(title: "保留", minutes: 10)])]), ProtocolBlock(title: "二", subblocks: [ProtocolSubblock(title: "乙", steps: [ProtocolStep(title: "操作二", minutes: 20)])])]); c.renumber()
        c.equipmentNeeded = ["仅在顶层声明的设备"]; c.estimatedTotalDurationMinutes = 999
        let target = c.blocks[1].subblocks[0].id
        XCTAssertTrue(c.moveStep(step.id, toGroup: target)); XCTAssertEqual(c.blocks[1].subblocks[0].steps.last?.notes, step.notes); XCTAssertEqual(c.blocks[1].subblocks[0].steps.last?.id, step.id)
        XCTAssertEqual(c.equipmentNeeded, ["仅在顶层声明的设备"]); XCTAssertEqual(c.estimatedTotalDurationMinutes, 999)
        try c.validated()
        let sourceGroup = c.blocks[0].subblocks[0].id; XCTAssertTrue(c.moveGroup(sourceGroup, toBlock: c.blocks[1].id)); XCTAssertEqual(c.blocks[1].subblocks.last?.id, sourceGroup)
        XCTAssertFalse(c.moveStep("missing", toGroup: target)); XCTAssertFalse(c.moveGroup(sourceGroup, toBlock: "missing"))
    }
    func testWorkHoursUseWallClockAcrossDaylightSaving() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        let start = c.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 7))!
        let p = Procedure(name: "测试", steps: [ProcedureStep(title: "操作", minutes: 30)])
        let plan = try Planner.schedule(experiment: Experiment(name: "实验", procedureID: p.id), procedure: p, in: Workspace(), starting: start, calendar: c)
        XCTAssertEqual(c.component(.hour, from: plan[0].start), 9)
    }
    func testUntilAndUnknownTimePreventSchedule() throws {
        var c = tree(ProtocolStep(title: "等待", minutes: 0)); var p = Procedure(name: "未知", content: c, status: .published)
        XCTAssertThrowsError(try Planner.schedule(experiment: Experiment(name: "实验", procedureID: p.id), procedure: p, in: Workspace(), starting: date(9), calendar: calendar))
        c.blocks[0].subblocks[0].steps[0].durationMinutes = 10; c.blocks[0].kind = "loop"; var l = ProtocolLoop(); l.type = "until"; l.until = "达到终点"; c.blocks[0].loop = l
        try c.validated(); p = Procedure(name: "终止条件", content: c)
        XCTAssertThrowsError(try c.executionItems())
    }
    func testPauseAndContinuousSemantics() throws {
        var step = ProtocolStep(title: "可暂停", minutes: 120); step.canPause = true
        let p = Procedure(name: "暂停", content: tree(step), status: .published)
        let plan = try Planner.schedule(experiment: Experiment(name: "实验", procedureID: p.id), procedure: p, in: Workspace(), starting: date(17), calendar: calendar)
        XCTAssertEqual(plan.count, 2); XCTAssertEqual(plan[0].end, date(18)); XCTAssertEqual(plan[1].start, date(9, day: 29))
        var tampered = plan; tampered[1].end = tampered[1].end.addingTimeInterval(60)
        XCTAssertThrowsError(try Planner.validate(tampered, procedure: p, versionID: p.currentVersion.id, workspace: Workspace(), preferences: SchedulePreferences(), calendar: calendar))
        step.requiresContinuous = true; XCTAssertThrowsError(try tree(step).validated())
    }
    func testUnattendedOvernightStillOccupiesInstrument() throws {
        let instrument = Instrument(name: "培养箱"); var w = Workspace(); w.instruments = [instrument]
        var step = ProtocolStep(title: "培养", minutes: 720, instrumentID: instrument.id); step.unattended = true; step.overnightSafe = true
        let p = Procedure(name: "培养", content: tree(step), status: .published)
        w.busyIntervals = [BusyInterval(title: "开会", start: date(17), end: date(18))]
        let exp = Experiment(name: "培养", procedureID: p.id)
        let plan = try Planner.schedule(experiment: exp, procedure: p, in: w, starting: date(17), calendar: calendar)
        XCTAssertEqual(plan.first?.start, date(17)); XCTAssertEqual(plan.first?.end, date(5, day: 29))
        w.busyIntervals.append(BusyInterval(title: "维护", start: date(18), end: date(9, day: 29), instrumentID: instrument.id))
        let later = try Planner.schedule(experiment: exp, procedure: p, in: w, starting: date(17), calendar: calendar)
        XCTAssertEqual(later.first?.start, date(9, day: 29))
    }
    func testBusyConflictSplitsPausableStep() throws {
        var step = ProtocolStep(title: "处理", minutes: 120); step.canPause = true
        var w = Workspace(); w.busyIntervals = [BusyInterval(title: "会议", start: date(10), end: date(11))]
        let p = Procedure(name: "处理", content: tree(step))
        let plan = try Planner.schedule(experiment: Experiment(name: "实验", procedureID: p.id), procedure: p, in: w, starting: date(9), calendar: calendar)
        XCTAssertEqual(plan.count, 2); XCTAssertEqual(plan[0].end, date(10)); XCTAssertEqual(plan[1].start, date(11))
    }
    func testSQLiteOptimisticRevisionAndLegacyMigration() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }; try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = WorkspaceFile(directory: dir)
        let id = UUID().uuidString; let stepID = UUID().uuidString
        let legacy = Data("""
        {"schemaVersion":1,"isDemo":false,"instruments":[],"procedures":[{"id":"\(id)","name":"旧版","note":"保留","steps":[{"id":"\(stepID)","title":"操作","minutes":30}]}],"experiments":[],"plan":[],"assistant":{"baseURL":"https://api.openai.com/v1","model":"old-model"}}
        """.utf8)
        try legacy.write(to: file.legacyURL)
        let migrated = try XCTUnwrap(file.load()); XCTAssertEqual(migrated.procedures[0].steps[0].id, stepID)
        XCTAssertEqual(try Data(contentsOf: file.legacyURL), legacy); XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        var next = migrated; next.revision += 1; try file.save(next, expectedRevision: migrated.revision)
        XCTAssertThrowsError(try file.save(migrated, expectedRevision: migrated.revision))
        XCTAssertEqual(try file.load()?.revision, next.revision)
    }
    func testMultipleModelsPersistAndConnectionSecurity() throws {
        var w = Workspace(); let connection = ProviderConnection(name: "本地", baseURL: "http://localhost:1234/v1")
        w.connections.append(connection); w.models.append(ModelProfile(connectionID: connection.id, name: "本地模型", model: "local")); w.routing.protocolBuilder = w.models.last?.id
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w)), w)
        try w.validated(); XCTAssertThrowsError(try ProviderConnection(baseURL: "http://example.com/v1").validated())
        XCTAssertThrowsError(try ProviderConnection(baseURL: "https://secret@example.com/v1").validated())
        XCTAssertEqual(try ProviderConnection(baseURL: "https://example.com/v1/chat/completions").endpoint("models").path, "/v1/models")
    }
    func testCalendarRoundTripFoldingAndRejectRecurrence() throws {
        let step = PlannedStep(experimentID: UUID(), title: String(repeating: "实验，步骤；", count: 20), instrumentID: nil, start: date(9), end: date(10))
        let ics = CalendarExchange.export([step]); let busy = try CalendarExchange.parse(ics, calendar: calendar)
        XCTAssertEqual(busy[0].title, step.title); XCTAssertEqual(busy[0].start, step.start)
        XCTAssertTrue(ics.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        XCTAssertThrowsError(try CalendarExchange.parse(ics.replacingOccurrences(of: "END:VEVENT", with: "RRULE:FREQ=DAILY\r\nEND:VEVENT")))
    }
}
