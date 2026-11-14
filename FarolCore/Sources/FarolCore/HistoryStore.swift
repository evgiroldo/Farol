import Darwin
import Foundation
import SQLite3

/// One minute of system-wide history (ADR 0013: aggregates outside incidents).
public struct SystemMinute: Sendable, Equatable {
    /// Start of the minute, seconds since 1970.
    public var start: Double
    public var averageBusyCores: Double
    public var peakBusyCores: Double
    public var swapped: Bool
    /// `nil` when memory pressure was unavailable for the whole minute.
    public var peakMemoryPressure: MemoryPressure?
    public var peakThermal: ThermalLevel

    public init(
        start: Double, averageBusyCores: Double, peakBusyCores: Double, swapped: Bool,
        peakMemoryPressure: MemoryPressure?, peakThermal: ThermalLevel
    ) {
        self.start = start
        self.averageBusyCores = averageBusyCores
        self.peakBusyCores = peakBusyCores
        self.swapped = swapped
        self.peakMemoryPressure = peakMemoryPressure
        self.peakThermal = peakThermal
    }
}

public struct Incident: Sendable, Equatable, Identifiable {
    public let id: Int64
    /// Seconds since 1970.
    public let started: Double
    public var ended: Double?
    public let reasons: AnomalyReason
    /// Boot time (seconds since 1970) of the session the incident belongs to.
    public let bootTime: Double
    /// True when the sentinel stopped (crash, logout, reboot) before the incident ended.
    public var interrupted: Bool

    public init(
        id: Int64, started: Double, ended: Double?, reasons: AnomalyReason, bootTime: Double,
        interrupted: Bool
    ) {
        self.id = id
        self.started = started
        self.ended = ended
        self.reasons = reasons
        self.bootTime = bootTime
        self.interrupted = interrupted
    }
}

/// A process's activity at one moment of an incident.
public struct IncidentProcessRecord: Sendable, Equatable {
    public let time: Double
    public let delta: ProcessDelta

    public init(time: Double, delta: ProcessDelta) {
        self.time = time
        self.delta = delta
    }
}

public enum HistoryError: Error, Equatable, CustomStringConvertible {
    case sqlite(code: Int32, message: String)
    /// The history directory or file is not safe to use (wrong owner, permissions, type).
    case unsafeFile(String)
    /// The database was written by another Farol version.
    case unsupportedSchema(found: Int32, supported: Int32)

    public var description: String {
        switch self {
        case .sqlite(let code, let message): "SQLite error \(code): \(message)"
        case .unsafeFile(let reason): "Unsafe history file: \(reason)"
        case .unsupportedSchema(let found, let supported):
            "History schema \(found) is not supported (this build supports \(supported))"
        }
    }
}

/// SQLite-backed history (ADR 0018). The sentinel is the only writer; the app opens it
/// read-only (ADR 0017). Not thread-safe: use it from one isolation domain.
///
/// The file is readable and writable by every process running as the same user
/// (permissions only keep other accounts out), so everything read back is treated as
/// untrusted input: rows are validated, reads are bounded and the schema is not trusted.
public final class HistoryStore {
    public static let schemaVersion: Int32 = 1
    /// Upper bound on rows returned by one read, so a bloated or tampered file cannot
    /// exhaust the app's memory.
    public static let defaultReadLimit = 100_000

    private var db: OpaquePointer?
    public let url: URL
    public let isReadOnly: Bool
    /// `url` with symlinks in parent directories resolved (e.g. `/var` → `/private/var`),
    /// because SQLite's no-follow mode rejects a symlink anywhere in the path. The final
    /// directory and file themselves are never symlinks (checked by `secureFiles`).
    private let path: String
    private let busyTimeoutMilliseconds: Int32

    private static let fileName = "history.sqlite"

    /// Default location: `~/Library/Application Support/Farol/history.sqlite`.
    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Farol", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    /// Opens (creating if needed, unless `readOnly`) the database.
    ///
    /// The directory must be a real directory (not a symlink) owned by the current user;
    /// the writer makes it `0700` and the file `0600`, and excludes the directory from
    /// backups (ADR 0013). The reader refuses files that are not private to the user.
    public init(url: URL, readOnly: Bool = false, busyTimeoutMilliseconds: Int32 = 2_000) throws {
        self.url = url
        self.isReadOnly = readOnly
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        try Self.secureFiles(at: url, create: !readOnly)
        path = try Self.resolvedPath(of: url)
        try open()
    }

    deinit { sqlite3_close(db) }

    // MARK: Writing

    public func append(_ minute: SystemMinute) throws {
        try run(
            """
            INSERT OR REPLACE INTO system_minutes
            (start, avg_busy_cores, peak_busy_cores, swapped, peak_pressure, peak_thermal)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            .double(minute.start), .double(minute.averageBusyCores), .double(minute.peakBusyCores),
            .int(minute.swapped ? 1 : 0), minute.peakMemoryPressure.map { .int(Int64($0.rawValue)) } ?? .null,
            .int(Int64(minute.peakThermal.rawValue)))
    }

    @discardableResult
    public func beginIncident(at time: Double, reasons: AnomalyReason, bootTime: Double) throws -> Int64 {
        try run(
            "INSERT INTO incidents (started, reasons, boot_time) VALUES (?, ?, ?)",
            .double(time), .int(Int64(reasons.rawValue)), .double(bootTime))
        return sqlite3_last_insert_rowid(db)
    }

    public func endIncident(_ id: Int64, at time: Double) throws {
        try run("UPDATE incidents SET ended = ? WHERE id = ? AND ended IS NULL", .double(time), .int(id))
    }

    /// Call when the sentinel starts: incidents left open by a crash, logout or reboot are
    /// closed at their last recorded sample and marked as interrupted.
    public func closeDanglingIncidents() throws {
        try run(
            """
            UPDATE incidents SET interrupted = 1, ended = COALESCE(
                (SELECT MAX(time) FROM incident_processes WHERE incident_id = incidents.id), started)
            WHERE ended IS NULL
            """)
    }

    /// Appends a batch of process records in one transaction (one disk write).
    public func append(_ records: [IncidentProcessRecord], incident: Int64) throws {
        guard !records.isEmpty else { return }
        try transaction {
            let stmt = try prepare(
                """
                INSERT INTO incident_processes
                (incident_id, time, pid, start_time, uid, name, cpu_seconds, disk_written, footprint)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(stmt) }
            for r in records {
                sqlite3_reset(stmt)
                let d = r.delta
                try bind(
                    stmt,
                    [
                        .int(incident), .double(r.time), .int(Int64(d.identity.pid)),
                        .int(Int64(bitPattern: d.identity.startTime)), .int(Int64(d.uid)), .text(d.name),
                        .double(d.cpuSeconds), .int(Int64(clamping: d.diskBytesWritten)),
                        .int(Int64(clamping: d.footprint)),
                    ])
                try check(sqlite3_step(stmt), expected: SQLITE_DONE)
            }
        }
    }

    /// Deletes everything older than `time` (retention, ADR 0018), then truncates the WAL
    /// so deleted rows do not linger in it. Open incidents are never purged.
    public func purge(olderThan time: Double) throws {
        try transaction {
            try run("DELETE FROM system_minutes WHERE start < ?", .double(time))
            try run("DELETE FROM incident_processes WHERE time < ?", .double(time))
            try run("DELETE FROM incidents WHERE ended IS NOT NULL AND ended < ?", .double(time))
        }
        try checkpoint()
    }

    /// "Delete history": closes the database, removes the database, WAL and shared-memory
    /// files, and starts an empty database. The data is gone from Farol's files; it may
    /// still exist in APFS snapshots or backups made before the directory was excluded
    /// (ADR 0019). Readers that still hold the old file must reopen.
    public func deleteAll() throws {
        precondition(!isReadOnly, "deleteAll requires the writer")
        sqlite3_close(db)
        db = nil
        for suffix in ["", "-wal", "-shm"] {
            let file = path + suffix
            if unlink(file) != 0 && errno != ENOENT {
                throw HistoryError.unsafeFile("cannot remove \(file): errno \(errno)")
            }
        }
        try Self.secureFiles(at: url, create: true)
        try open()
    }

    /// Moves WAL content into the database and truncates the WAL file.
    /// Returns `false` if a reader prevented a complete checkpoint.
    @discardableResult
    public func checkpoint() throws -> Bool {
        let busy = try query("PRAGMA wal_checkpoint(TRUNCATE)") { s -> Int32? in sqlite3_column_int(s, 0) }
        return busy.first == 0
    }

    // MARK: Reading

    public func minutes(since time: Double, limit: Int = defaultReadLimit) throws -> [SystemMinute] {
        try query(
            """
            SELECT start, avg_busy_cores, peak_busy_cores, swapped, peak_pressure, peak_thermal
            FROM system_minutes WHERE start >= ? ORDER BY start LIMIT ?
            """, .double(time), .int(Int64(limit))
        ) { s in
            SystemMinute(
                start: sqlite3_column_double(s, 0),
                averageBusyCores: sqlite3_column_double(s, 1),
                peakBusyCores: sqlite3_column_double(s, 2),
                swapped: sqlite3_column_int(s, 3) != 0,
                peakMemoryPressure: sqlite3_column_type(s, 4) == SQLITE_NULL
                    ? nil : MemoryPressure(rawValue: Int(sqlite3_column_int(s, 4))),
                peakThermal: ThermalLevel(rawValue: Int(sqlite3_column_int(s, 5))) ?? .nominal)
        }
    }

    public func incidents(since time: Double, limit: Int = defaultReadLimit) throws -> [Incident] {
        try query(
            """
            SELECT id, started, ended, reasons, boot_time, interrupted FROM incidents
            WHERE COALESCE(ended, started) >= ? ORDER BY started LIMIT ?
            """, .double(time), .int(Int64(limit))
        ) { s in
            Incident(
                id: sqlite3_column_int64(s, 0),
                started: sqlite3_column_double(s, 1),
                ended: sqlite3_column_type(s, 2) == SQLITE_NULL ? nil : sqlite3_column_double(s, 2),
                reasons: AnomalyReason(rawValue: Int(sqlite3_column_int(s, 3))),
                bootTime: sqlite3_column_double(s, 4),
                interrupted: sqlite3_column_int(s, 5) != 0)
        }
    }

    /// Process records of one incident. Rows that fail validation (non-positive PID,
    /// missing name) are skipped instead of trusted.
    public func processes(inIncident id: Int64, limit: Int = defaultReadLimit) throws -> [IncidentProcessRecord] {
        try query(
            """
            SELECT time, pid, start_time, uid, name, cpu_seconds, disk_written, footprint
            FROM incident_processes WHERE incident_id = ? ORDER BY time LIMIT ?
            """, .int(id), .int(Int64(limit))
        ) { s -> IncidentProcessRecord? in
            let pid = sqlite3_column_int64(s, 1)
            guard pid > 0, pid <= Int64(Int32.max), let name = Self.text(s, 4) else { return nil }
            return IncidentProcessRecord(
                time: sqlite3_column_double(s, 0),
                delta: ProcessDelta(
                    identity: ProcessIdentity(
                        pid: pid_t(pid), startTime: UInt64(bitPattern: sqlite3_column_int64(s, 2))),
                    name: name,
                    uid: uid_t(truncatingIfNeeded: max(0, sqlite3_column_int64(s, 3))),
                    cpuSeconds: max(0, sqlite3_column_double(s, 5)),
                    diskBytesWritten: UInt64(max(0, sqlite3_column_int64(s, 6))),
                    footprint: UInt64(max(0, sqlite3_column_int64(s, 7)))))
        }
    }

    // MARK: Opening

    private func open() throws {
        let flags =
            (isReadOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE)
            | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            db = nil
            throw HistoryError.sqlite(code: rc, message: message)
        }
        sqlite3_busy_timeout(db, busyTimeoutMilliseconds)
        // Bound any single string or blob, so a tampered row cannot be huge.
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1 << 20)
        // Do not run functions or views defined by whoever last wrote the schema.
        try execute("PRAGMA trusted_schema=OFF")
        try execute("PRAGMA cell_size_check=ON")
        try execute("PRAGMA foreign_keys=ON")

        if isReadOnly {
            try execute("PRAGMA query_only=ON")
            let version = try userVersion()
            guard version == Self.schemaVersion else {
                throw HistoryError.unsupportedSchema(found: version, supported: Self.schemaVersion)
            }
            return
        }
        let mode = try query("PRAGMA journal_mode=WAL") { Self.text($0, 0) }.first
        guard mode == "wal" else {
            throw HistoryError.sqlite(code: SQLITE_ERROR, message: "WAL mode refused (got \(mode ?? "nil"))")
        }
        try execute("PRAGMA journal_size_limit=0")
        try execute("PRAGMA secure_delete=ON")
        try migrate()
    }

    private static func resolvedPath(of url: URL) throws -> String {
        let dir = url.deletingLastPathComponent().path
        guard let resolved = realpath(dir, nil) else { throw HistoryError.unsafeFile("cannot resolve \(dir)") }
        defer { free(resolved) }
        return String(cString: resolved) + "/" + url.lastPathComponent
    }

    /// Validates (and, for the writer, creates and tightens) the directory and files
    /// without following symlinks, using file descriptors to avoid check-then-use races.
    private static func secureFiles(at url: URL, create: Bool) throws {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        if create {
            if mkdir(dir.path, 0o700) != 0 && errno != EEXIST {
                throw HistoryError.unsafeFile("cannot create \(dir.path): errno \(errno)")
            }
        }
        let dirFD = Darwin.open(dir.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw HistoryError.unsafeFile("\(dir.path) is missing or a symlink") }
        defer { close(dirFD) }
        try checkOwned(dirFD, directory: true, path: dir.path, tighten: create ? 0o700 : nil)

        for suffix in ["", "-wal", "-shm"] {
            let mustExist = suffix.isEmpty
            let flags = (create ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC | (create && mustExist ? O_CREAT : 0)
            let fd = openat(dirFD, name + suffix, flags, mode_t(0o600))
            if fd < 0 {
                if errno == ENOENT && !mustExist { continue }
                throw HistoryError.unsafeFile("\(name + suffix) cannot be opened safely: errno \(errno)")
            }
            defer { close(fd) }
            try checkOwned(fd, directory: false, path: name + suffix, tighten: create ? 0o600 : nil)
        }

        if create {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dirURL = dir
            try dirURL.setResourceValues(values)
        }
    }

    /// Requires the descriptor to be owned by the current user, of the expected type, with
    /// no hard links (files) and no access for group or others. `tighten` fixes the mode
    /// instead of rejecting it.
    private static func checkOwned(_ fd: Int32, directory: Bool, path: String, tighten: mode_t?) throws {
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw HistoryError.unsafeFile("cannot stat \(path)") }
        let type = st.st_mode & S_IFMT
        guard type == (directory ? S_IFDIR : S_IFREG) else {
            throw HistoryError.unsafeFile("\(path) has an unexpected file type")
        }
        guard st.st_uid == getuid() else { throw HistoryError.unsafeFile("\(path) is not owned by this user") }
        if !directory && st.st_nlink > 1 { throw HistoryError.unsafeFile("\(path) has extra hard links") }
        if let mode = tighten {
            guard fchmod(fd, mode) == 0 else { throw HistoryError.unsafeFile("cannot chmod \(path)") }
        } else if st.st_mode & 0o077 != 0 {
            throw HistoryError.unsafeFile("\(path) is accessible to other users")
        }
    }

    // MARK: Schema

    /// Migration `i` upgrades schema version `i` to `i + 1`.
    private static let migrations: [String] = [
        """
        CREATE TABLE system_minutes (
            start REAL PRIMARY KEY,
            avg_busy_cores REAL NOT NULL,
            peak_busy_cores REAL NOT NULL,
            swapped INTEGER NOT NULL,
            peak_pressure INTEGER,
            peak_thermal INTEGER NOT NULL
        );
        CREATE TABLE incidents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started REAL NOT NULL,
            ended REAL,
            reasons INTEGER NOT NULL,
            boot_time REAL NOT NULL,
            interrupted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE incident_processes (
            incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
            time REAL NOT NULL,
            pid INTEGER NOT NULL,
            start_time INTEGER NOT NULL,
            uid INTEGER NOT NULL,
            name TEXT NOT NULL,
            cpu_seconds REAL NOT NULL,
            disk_written INTEGER NOT NULL,
            footprint INTEGER NOT NULL
        );
        CREATE INDEX incident_processes_by_incident ON incident_processes(incident_id, time);
        CREATE INDEX incident_processes_by_time ON incident_processes(time);
        """
    ]

    private func userVersion() throws -> Int32 {
        try query("PRAGMA user_version") { s -> Int32? in sqlite3_column_int(s, 0) }.first ?? 0
    }

    private func migrate() throws {
        let version = try userVersion()
        guard version <= Self.schemaVersion else {
            throw HistoryError.unsupportedSchema(found: version, supported: Self.schemaVersion)
        }
        for step in Int(version)..<Int(Self.schemaVersion) {
            try transaction {
                try execute(Self.migrations[step])
                try execute("PRAGMA user_version = \(step + 1)")
            }
        }
    }

    // MARK: SQLite helpers

    private enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    /// Runs `body` in a write transaction; any error rolls it back, so a failure can never
    /// leave a transaction open and silently stop later writes.
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? ""
            sqlite3_free(error)
            throw HistoryError.sqlite(code: rc, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        return stmt
    }

    private func bind(_ stmt: OpaquePointer?, _ values: [Value]) throws {
        for (i, v) in values.enumerated() {
            let index = Int32(i + 1)
            switch v {
            case .int(let x): try check(sqlite3_bind_int64(stmt, index, x))
            case .double(let x): try check(sqlite3_bind_double(stmt, index, x))
            case .text(let x): try check(sqlite3_bind_text(stmt, index, x, -1, Self.transient))
            case .null: try check(sqlite3_bind_null(stmt, index))
            }
        }
    }

    private func run(_ sql: String, _ values: Value...) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, values)
        try check(sqlite3_step(stmt), expected: SQLITE_DONE)
    }

    /// Runs a query; rows for which `row` returns `nil` are skipped.
    private func query<T>(_ sql: String, _ values: Value..., row: (OpaquePointer?) -> T?) throws -> [T] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, values)
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            try check(rc, expected: SQLITE_ROW)
            if let value = row(stmt) { out.append(value) }
        }
        return out
    }

    private func check(_ rc: Int32, expected: Int32 = SQLITE_OK) throws {
        guard rc == expected else {
            throw HistoryError.sqlite(code: rc, message: String(cString: sqlite3_errmsg(db)))
        }
    }
}
