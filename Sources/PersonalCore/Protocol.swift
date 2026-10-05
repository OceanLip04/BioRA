import Foundation

public struct ProtocolLoop: Codable, Equatable, Sendable {
    public var type = "count"
    public var count: Int? = 2
    public var until: String?
    public init() {}
}

public struct ProtocolStep: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var order = 1
    public var title = ""
    public var description = ""
    public var durationMinutes = 0
    public var canPause = false
    public var overnightSafe = false
    public var requiresContinuous = false
    public var reagents: [String] = []
    public var equipmentNeeded: [String] = []
    public var notes = ""
    public var instrumentID: UUID?
    public var unattended = false
    public var minutes: Int { durationMinutes }
    public init(title: String = "", minutes: Int = 0, instrumentID: UUID? = nil) {
        self.title = title; self.description = title; self.durationMinutes = minutes; self.instrumentID = instrumentID
    }
    enum CodingKeys: String, CodingKey {
        case id, order, title, description, reagents, notes
        case durationMinutes = "duration_minutes", canPause = "can_pause", overnightSafe = "overnight_safe"
        case requiresContinuous = "requires_continuous", equipmentNeeded = "equipment_needed"
        case instrumentID = "instrument_id", unattended
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); order = try c.decode(Int.self, forKey: .order)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? title
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        canPause = try c.decodeIfPresent(Bool.self, forKey: .canPause) ?? false
        overnightSafe = try c.decodeIfPresent(Bool.self, forKey: .overnightSafe) ?? false
        requiresContinuous = try c.decodeIfPresent(Bool.self, forKey: .requiresContinuous) ?? false
        reagents = try c.decodeIfPresent([String].self, forKey: .reagents) ?? []
        equipmentNeeded = try c.decodeIfPresent([String].self, forKey: .equipmentNeeded) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        instrumentID = try c.decodeIfPresent(UUID.self, forKey: .instrumentID)
        unattended = try c.decodeIfPresent(Bool.self, forKey: .unattended) ?? false
    }
}

public struct ProtocolSubblock: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var order = 1
    public var title = "动作分组"
    public var description = ""
    public var kind = "section"
    public var loop: ProtocolLoop?
    public var steps: [ProtocolStep] = []
    public init(title: String = "动作分组", steps: [ProtocolStep] = []) { self.title = title; self.steps = steps }
    enum CodingKeys: String, CodingKey { case id, order, title, description, kind, loop, steps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); order = try c.decode(Int.self, forKey: .order)
        title = try c.decode(String.self, forKey: .title); description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "section"; loop = try c.decodeIfPresent(ProtocolLoop.self, forKey: .loop)
        steps = try c.decode([ProtocolStep].self, forKey: .steps)
    }
}

public struct ProtocolBlock: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var order = 1
    public var title = "主要阶段"
    public var description = ""
    public var kind = "section"
    public var loop: ProtocolLoop?
    public var subblocks: [ProtocolSubblock] = []
    public init(title: String = "主要阶段", subblocks: [ProtocolSubblock] = []) { self.title = title; self.subblocks = subblocks }
    enum CodingKeys: String, CodingKey { case id, order, title, description, kind, loop, subblocks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); order = try c.decode(Int.self, forKey: .order)
        title = try c.decode(String.self, forKey: .title); description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "section"; loop = try c.decodeIfPresent(ProtocolLoop.self, forKey: .loop)
        subblocks = try c.decode([ProtocolSubblock].self, forKey: .subblocks)
    }
}

public enum MaterialCategory: String, Codable, CaseIterable, Sendable {
    case sample, reagent, consumable, equipment, other
    public var title: String {
        switch self { case .sample: "样品"; case .reagent: "试剂"; case .consumable: "耗材"; case .equipment: "设备"; case .other: "其他" }
    }
}

// Preparation state belongs to the workspace, never to the model-generated recipe.
public struct ProtocolMaterial: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var category: MaterialCategory = .reagent
    public var name: String
    public var specification = ""
    public var quantity = ""
    public var notes = ""
    public init(name: String, category: MaterialCategory = .reagent, specification: String = "", quantity: String = "", notes: String = "") {
        self.name = name; self.category = category; self.specification = specification; self.quantity = quantity; self.notes = notes
    }
}

public struct ProtocolContent: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var view = "hierarchy_vertical"
    public var objective = ""
    public var materials: [ProtocolMaterial] = []
    public var principles: [String] = []
    public var precautions: [String] = []
    public var blocks: [ProtocolBlock] = []
    public var estimatedTotalDurationMinutes = 0
    public var equipmentNeeded: [String] = []
    public init(blocks: [ProtocolBlock] = []) { self.blocks = blocks }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", view, blocks, objective, materials, principles, precautions
        case estimatedTotalDurationMinutes = "estimated_total_duration_minutes", equipmentNeeded = "equipment_needed"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        view = try c.decodeIfPresent(String.self, forKey: .view) ?? "hierarchy_vertical"
        objective = try c.decodeIfPresent(String.self, forKey: .objective) ?? ""
        materials = try c.decodeIfPresent([ProtocolMaterial].self, forKey: .materials) ?? []
        principles = try c.decodeIfPresent([String].self, forKey: .principles) ?? []
        precautions = try c.decodeIfPresent([String].self, forKey: .precautions) ?? []
        blocks = try c.decode([ProtocolBlock].self, forKey: .blocks)
        estimatedTotalDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedTotalDurationMinutes) ?? 0
        equipmentNeeded = try c.decodeIfPresent([String].self, forKey: .equipmentNeeded) ?? []
    }
    public var atomicSteps: [ProtocolStep] { blocks.sorted { $0.order < $1.order }.flatMap { $0.subblocks.sorted { $0.order < $1.order }.flatMap { $0.steps.sorted { $0.order < $1.order } } } }
    public mutating func renumber() {
        var stepOrder = 0
        for b in blocks.indices {
            blocks[b].order = b + 1
            for s in blocks[b].subblocks.indices {
                blocks[b].subblocks[s].order = s + 1
                for t in blocks[b].subblocks[s].steps.indices {
                    stepOrder += 1; blocks[b].subblocks[s].steps[t].order = stepOrder
                }
            }
        }
        // Reordering must not overwrite imported summary metadata or resource declarations.
    }
    @discardableResult public mutating func moveStep(_ id: String, toGroup target: String, before beforeID: String? = nil) -> Bool {
        guard blocks.contains(where: { $0.subblocks.contains { $0.id == target } }) else { return false }
        if id == beforeID { return false }
        var moved: ProtocolStep?
        for b in blocks.indices { for g in blocks[b].subblocks.indices {
            if let i = blocks[b].subblocks[g].steps.firstIndex(where: { $0.id == id }) { moved = blocks[b].subblocks[g].steps.remove(at: i) }
        } }
        guard let moved else { return false }
        for b in blocks.indices { if let g = blocks[b].subblocks.firstIndex(where: { $0.id == target }) {
            let index = beforeID.flatMap { before in blocks[b].subblocks[g].steps.firstIndex { $0.id == before } } ?? blocks[b].subblocks[g].steps.count
            blocks[b].subblocks[g].steps.insert(moved, at: index); renumber(); return true
        } }; return false
    }
    @discardableResult public mutating func moveGroup(_ id: String, toBlock target: String, before beforeID: String? = nil) -> Bool {
        guard blocks.contains(where: { $0.id == target }), id != beforeID else { return false }
        var moved: ProtocolSubblock?
        for b in blocks.indices { if let g = blocks[b].subblocks.firstIndex(where: { $0.id == id }) { moved = blocks[b].subblocks.remove(at: g) } }
        guard let moved, let b = blocks.firstIndex(where: { $0.id == target }) else { return false }
        let index = beforeID.flatMap { before in blocks[b].subblocks.firstIndex { $0.id == before } } ?? blocks[b].subblocks.count
        blocks[b].subblocks.insert(moved, at: index); renumber(); return true
    }
    public func validated() throws {
        guard objective.count <= 10000, materials.count <= 500, principles.count <= 100, precautions.count <= 100,
              (principles + precautions).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 5000 }) else {
            throw WorkspaceError.invalid("实验目的、材料、原理或注意事项的文本/条目超出限制或包含空条目。")
        }
        var materialIDs = Set<String>()
        for material in materials {
            guard !material.id.isEmpty, material.id.count <= 128, materialIDs.insert(material.id).inserted,
                  !material.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, material.name.count <= 255,
                  material.specification.count <= 2000, material.quantity.count <= 1000, material.notes.count <= 5000 else {
                throw WorkspaceError.invalid("材料需要非空名称、唯一 ID 及长度有效的规格、用量、备注。")
            }
        }
        guard schemaVersion == 3, view == "hierarchy_vertical", !blocks.isEmpty, blocks.count <= 100,
              atomicSteps.count > 0, atomicSteps.count <= 2000, estimatedTotalDurationMinutes >= 0 else { throw WorkspaceError.invalid("Protocol 需要有效的三层结构和至少一个原子操作。") }
        var ids = materialIDs; var orders = Set<Int>()
        func node(_ id: String, _ title: String) throws {
            guard !id.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ids.insert(id).inserted else {
                throw WorkspaceError.invalid("Protocol 节点名称不能为空，ID 必须唯一。")
            }
        }
        func loop(_ kind: String, _ value: ProtocolLoop?) throws {
            guard kind == "section" || kind == "loop" else { throw WorkspaceError.invalid("无效的阶段类型。") }
            if kind == "loop" {
                guard let value, (value.type == "count" && (1...100).contains(value.count ?? 0)) || (value.type == "until" && !(value.until ?? "").isEmpty) else { throw WorkspaceError.invalid("循环需要 1–100 次或明确的终止条件。") }
            } else if value != nil { throw WorkspaceError.invalid("普通阶段不能带循环定义。") }
        }
        guard blocks.allSatisfy({ $0.order > 0 }), Set(blocks.map(\.order)).count == blocks.count else { throw WorkspaceError.invalid("阶段顺序重复或无效。") }
        for block in blocks {
            try node(block.id, block.title); try loop(block.kind, block.loop)
            guard !block.subblocks.isEmpty, block.subblocks.count <= 100, block.subblocks.allSatisfy({ $0.order > 0 }), Set(block.subblocks.map(\.order)).count == block.subblocks.count else { throw WorkspaceError.invalid("每个阶段需要分组且分组顺序不能重复。") }
            for group in block.subblocks {
                try node(group.id, group.title); try loop(group.kind, group.loop)
                guard !group.steps.isEmpty else { throw WorkspaceError.invalid("每个分组需要至少一个原子操作。") }
                for step in group.steps {
                    try node(step.id, step.title.isEmpty ? step.description : step.title)
                    guard step.order > 0, orders.insert(step.order).inserted, (0...7200).contains(step.durationMinutes), !(step.canPause && step.requiresContinuous) else { throw WorkspaceError.invalid("步骤顺序、耗时或连续/暂停设置无效。") }
                    guard step.id.count <= 128, step.title.count <= 255, step.description.count <= 10000, step.notes.count <= 2000,
                          step.reagents.count <= 100, step.equipmentNeeded.count <= 50 else { throw WorkspaceError.invalid("原子操作的文本或资源条目超过 V3 限制。") }
                }
            }
        }
    }
    /// A conservative semantic guard for newly generated documents, not a migration of historical recipes.
    public func validatedGeneratedDocument() throws {
        try validated()
        guard !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("缺少实验目的，请在 objective 中填写而不是创建目的步骤。") }
        func normalized(_ value: String) -> String {
            value.lowercased().filter { !$0.isWhitespace && !"：:。.,，-_/()（）".contains($0) }
        }
        let headings = Set(["实验目的", "目的", "实验材料", "材料", "材料清单", "所需材料", "试剂清单", "所需试剂", "设备清单", "原理", "实验原理", "注意事项", "安全注意事项", "objective", "purpose", "materials", "materiallist", "reagents", "equipment", "principles", "precautions", "safetynotes"])
        let titles = blocks.flatMap { [$0.title] + $0.subblocks.map(\.title) } + atomicSteps.map(\.title)
        guard !titles.contains(where: { headings.contains(normalized($0)) }) else {
            throw WorkspaceError.invalid("目的/材料/原理/注意事项不能成为操作阶段、分组或步骤，请移到对应顶层字段。实际配制、称量、装载等操作仍保留在 blocks。")
        }
        let inventory = Set(materials.map { normalized($0.name) })
        guard !atomicSteps.contains(where: { inventory.contains(normalized($0.title)) }) else {
            throw WorkspaceError.invalid("检测到只有材料名称、没有操作的步骤。材料放 materials；steps 必须描述实际动作。")
        }
    }
    public func executionItems() throws -> [ExecutionItem] {
        try validated()
        func iterations(_ kind: String, _ loop: ProtocolLoop?) throws -> Int {
            if kind != "loop" { return 1 }
            guard loop?.type == "count", let count = loop?.count else { throw WorkspaceError.invalid("until 循环需改为明确次数后才能排程。") }
            return count
        }
        var items: [ExecutionItem] = []
        for b in blocks.sorted(by: { $0.order < $1.order }) {
            for bi in 0..<(try iterations(b.kind, b.loop)) {
                for s in b.subblocks.sorted(by: { $0.order < $1.order }) {
                    for si in 0..<(try iterations(s.kind, s.loop)) {
                        for step in s.steps.sorted(by: { $0.order < $1.order }) {
                            guard items.count < 10000 else { throw WorkspaceError.invalid("展开后的循环超过 10000 个执行项。") }
                            items.append(ExecutionItem(blockID: b.id, subblockID: s.id, iteration: "\(bi + 1).\(si + 1)", step: step))
                        }
                    }
                }
            }
        }
        return items
    }
}

public struct ExecutionItem: Equatable, Sendable {
    public var blockID: String; public var subblockID: String; public var iteration: String; public var step: ProtocolStep
}
public enum VersionStatus: String, Codable, CaseIterable, Sendable { case draft, published, retired }
public struct ProcedureVersion: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var number: Int; public var status: VersionStatus
    public var content: ProtocolContent; public var createdAt = Date()
    public init(number: Int = 1, status: VersionStatus = .published, content: ProtocolContent) { self.number = number; self.status = status; self.content = content }
}

// Decoder for the first preview; only used for explicit, lossless migration.
public struct ProcedureStep: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var minutes: Int; public var instrumentID: UUID?
    public init(title: String, minutes: Int, instrumentID: UUID? = nil) { self.title = title; self.minutes = minutes; self.instrumentID = instrumentID }
}
public struct Procedure: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var note: String
    public var revision = 1; public var versions: [ProcedureVersion]
    public var currentVersion: ProcedureVersion { versions.filter { $0.status == .published }.max { $0.number < $1.number } ?? versions.max { $0.number < $1.number }! }
    public var steps: [ProtocolStep] { currentVersion.content.atomicSteps }
    public var totalMinutes: Int { (try? currentVersion.content.executionItems().reduce(0) { $0 + $1.step.durationMinutes }) ?? currentVersion.content.estimatedTotalDurationMinutes }
    public init(id: UUID = UUID(), name: String, note: String = "", steps: [ProcedureStep]) {
        self.id = id; self.name = name; self.note = note
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "实验流程", subblocks: [ProtocolSubblock(title: "操作步骤", steps: steps.map { old in
            var step = ProtocolStep(title: old.title, minutes: old.minutes, instrumentID: old.instrumentID); step.id = old.id.uuidString; return step
        })])]); content.renumber()
        var version = ProcedureVersion(content: content); version.id = id; versions = [version]
    }
    public init(name: String, note: String = "", content: ProtocolContent, status: VersionStatus = .draft) {
        self.name = name; self.note = note; versions = [ProcedureVersion(status: status, content: content)]
    }
    enum CodingKeys: String, CodingKey { case id, name, note, revision, versions, steps }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id); let name = try c.decode(String.self, forKey: .name)
        let note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        if let versions = try c.decodeIfPresent([ProcedureVersion].self, forKey: .versions) {
            guard !versions.isEmpty else { throw WorkspaceError.invalid("Protocol 版本列表为空。") }
            self.init(name: name, note: note, content: versions[0].content, status: versions[0].status)
            self.id = id; self.name = name; self.note = note; self.versions = versions
            revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        } else { self.init(id: id, name: name, note: note, steps: try c.decode([ProcedureStep].self, forKey: .steps)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(note, forKey: .note)
        try c.encode(revision, forKey: .revision); try c.encode(versions, forKey: .versions)
    }
}
