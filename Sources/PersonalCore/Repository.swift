import CSQLite
import Foundation

public struct WorkspaceFile: Sendable {
    public let directory: URL
    public var url: URL { directory.appendingPathComponent("workspace.sqlite") }
    public var legacyURL: URL { directory.appendingPathComponent("workspace.json") }
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> Workspace? {
        if FileManager.default.fileExists(atPath: url.path) {
            let db = try Database(url: url, create: false)
            guard let data = try db.payload() else { throw WorkspaceError.invalid("数据库没有工作区快照，已停止写入。") }
            let value = try JSONDecoder().decode(Workspace.self, from: data); try value.validated(); return value
        }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let data = try Data(contentsOf: legacyURL)
        let value = try JSONDecoder().decode(Workspace.self, from: data); try value.validated()
        // JSON is retained untouched as the pre-migration backup.
        try save(value); return value
    }
    public func save(_ workspace: Workspace, expectedRevision: Int? = nil) throws {
        try workspace.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(workspace)
        let db = try Database(url: url, create: true)
        try db.execute("CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, payload BLOB NOT NULL)")
        try db.execute("BEGIN IMMEDIATE")
        do {
            if let expectedRevision, let original = try db.payload(), try JSONDecoder().decode(Workspace.self, from: original).revision != expectedRevision {
                throw WorkspaceError.invalid("工作区已被另一个窗口或进程修改，请重新打开 App 后再保存。")
            }
            let stmt = try db.prepare("INSERT INTO workspace(id,revision,payload) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,payload=excluded.payload")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, Int64(workspace.revision))
            let status = data.withUnsafeBytes { bytes in sqlite3_bind_blob(stmt, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK, sqlite3_step(stmt) == SQLITE_DONE else { throw db.error() }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func export(_ workspace: Workspace, to destination: URL) throws {
        try workspace.validated(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(workspace).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

private final class Database {
    private var handle: OpaquePointer?
    init(url: URL, create: Bool) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else { let failure = error(); if let handle { sqlite3_close(handle) }; handle = nil; throw failure }
        sqlite3_busy_timeout(handle, 5000)
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func error() -> WorkspaceError { .invalid("本地数据库操作失败：\(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开文件")") }
    func execute(_ sql: String) throws { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() } }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error() }; return stmt
    }
    func payload() throws -> Data? {
        let stmt = try prepare("SELECT payload FROM workspace WHERE id=1"); defer { sqlite3_finalize(stmt) }
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let pointer = sqlite3_column_blob(stmt, 0) else { throw error() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(stmt, 0)))
    }
}
