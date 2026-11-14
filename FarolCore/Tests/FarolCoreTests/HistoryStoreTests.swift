import Darwin
import Foundation
import SQLite3
import Testing

@testable import FarolCore

@Suite("HistoryStore")
struct HistoryStoreTests {
    let root: URL
    let dir: URL
    var dbURL: URL { dir.appending(path: "history.sqlite") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "farol-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        dir = root.appending(path: "Farol", directoryHint: .isDirectory)
    }

    func makeStore(busyTimeout: Int32 = 2_000) throws -> HistoryStore {
        try HistoryStore(url: dbURL, busyTimeoutMilliseconds: busyTimeout)
    }

    func minute(_ start: Double, cores: Double = 1) -> SystemMinute {
        SystemMinute(
            start: start, averageBusyCores: cores, peakBusyCores: cores * 2, swapped: false,
            peakMemoryPressure: .normal, peakThermal: .nominal)
    }

    func record(time: Double, pid: pid_t = 42, name: String = "Safari Web Content") -> IncidentProcessRecord {
        IncidentProcessRecord(
            time: time,
            delta: ProcessDelta(
                identity: ProcessIdentity(pid: pid, startTime: UInt64.max - 1), name: name, uid: 501,
                cpuSeconds: 0.75, diskBytesWritten: 4096, footprint: 1 << 20))
    }

    /// Raw SQLite access, to play the part of another process or a tampered file.
    func raw(_ sql: String, at url: URL? = nil) throws {
        var db: OpaquePointer?
        guard sqlite3_open((url ?? dbURL).path, &db) == SQLITE_OK else { throw HistoryError.unsafeFile("raw open") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryError.sqlite(code: 0, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: Files and permissions

    @Test func onlyTheUserCanReadTheHistory() throws {
        let store = try makeStore()
        try store.append(minute(1))
        func mode(_ path: String) throws -> Int? {
            try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        }
        #expect(try mode(dir.path) == 0o700)
        #expect(try mode(store.url.path) == 0o600)
        #expect(try mode(store.url.path + "-wal") == 0o600)
    }

    @Test func historyIsExcludedFromBackups() throws {
        _ = try makeStore()
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func refusesASymlinkedDirectory() throws {
        let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir, withDestinationURL: elsewhere)
        #expect(throws: HistoryError.self) { try makeStore() }
        // The target directory was not touched.
        let mode = try FileManager.default.attributesOfItem(atPath: elsewhere.path)[.posixPermissions] as? Int
        #expect(mode != 0o700)
    }

    @Test func refusesASymlinkedDatabase() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let target = root.appending(path: "target.sqlite")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        try FileManager.default.createSymbolicLink(at: dbURL, withDestinationURL: target)
        #expect(throws: HistoryError.self) { try makeStore() }
    }

    @Test func readerRefusesAFileOthersCanRead() throws {
        _ = try makeStore()
        chmod(dbURL.path, 0o644)
        #expect(throws: HistoryError.self) { try HistoryStore(url: dbURL, readOnly: true) }
    }

    @Test func refusesANewerSchema() throws {
        _ = try makeStore()
        try raw("PRAGMA user_version = 99")
        #expect(throws: HistoryError.unsupportedSchema(found: 99, supported: HistoryStore.schemaVersion)) {
            try makeStore()
        }
        #expect(throws: HistoryError.unsupportedSchema(found: 99, supported: HistoryStore.schemaVersion)) {
            try HistoryStore(url: dbURL, readOnly: true)
        }
    }

    // MARK: Round trips

    @Test func minutesRoundTrip() throws {
        let store = try makeStore()
        try store.append(minute(60))
        let stored = SystemMinute(
            start: 120, averageBusyCores: 2.5, peakBusyCores: 6, swapped: true, peakMemoryPressure: nil,
            peakThermal: .serious)
        try store.append(stored)
        #expect(try store.minutes(since: 100) == [stored])
    }

    @Test func incidentsAndProcessesRoundTrip() throws {
        let store = try makeStore()
        let id = try store.beginIncident(at: 1000, reasons: [.cpu, .swapping], bootTime: 500)
        try store.append([record(time: 1001)], incident: id)
        try store.endIncident(id, at: 1040)

        #expect(
            try store.incidents(since: 0) == [
                Incident(
                    id: id, started: 1000, ended: 1040, reasons: [.cpu, .swapping], bootTime: 500, interrupted: false)
            ])
        #expect(try store.processes(inIncident: id) == [record(time: 1001)])
    }

    @Test func readOnlyStoreCannotWrite() throws {
        let writer = try makeStore()
        try writer.append(minute(10))
        let reader = try HistoryStore(url: writer.url, readOnly: true)
        #expect(try reader.minutes(since: 0).count == 1)
        #expect(throws: HistoryError.self) { try reader.append(minute(20)) }
    }

    @Test func reopeningKeepsData() throws {
        do { try makeStore().append(minute(10)) }
        #expect(try makeStore().minutes(since: 0).count == 1)
    }

    // MARK: Deletion and retention

    /// Review finding (reproduced): in WAL mode the deleted rows stayed in the -wal file.
    @Test func deleteAllLeavesNoTraceInAnyFile() throws {
        let store = try makeStore()
        let id = try store.beginIncident(at: 1, reasons: .cpu, bootTime: 0)
        try store.append((0..<200).map { record(time: Double($0), name: "SECRET-APP-NAME") }, incident: id)
        try store.deleteAll()

        #expect(try store.incidents(since: 0).isEmpty)
        let marker = Data("SECRET-APP-NAME".utf8)
        for suffix in ["", "-wal", "-shm"] {
            guard let data = FileManager.default.contents(atPath: store.url.path + suffix) else { continue }
            #expect(data.range(of: marker) == nil, "found deleted data in history.sqlite\(suffix)")
        }
        try store.append(minute(5))  // still usable afterwards
        #expect(try store.minutes(since: 0).count == 1)
    }

    /// Review finding (reproduced): one failed purge left a transaction open, and every
    /// later write was silently lost.
    @Test func failedPurgeDoesNotBreakLaterWrites() throws {
        let store = try makeStore(busyTimeout: 50)
        try store.append(minute(1))
        // Another process holds the write lock.
        var other: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &other) == SQLITE_OK)
        defer { sqlite3_close(other) }
        #expect(sqlite3_exec(other, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        #expect(throws: HistoryError.self) { try store.purge(olderThan: 100) }
        sqlite3_exec(other, "ROLLBACK", nil, nil, nil)

        try store.append(minute(200))
        let id = try store.beginIncident(at: 300, reasons: .cpu, bootTime: 0)
        try store.append([record(time: 301)], incident: id)
        let reader = try HistoryStore(url: dbURL, readOnly: true)
        #expect(try reader.minutes(since: 0).count == 2)
        #expect(try reader.processes(inIncident: id).count == 1)
    }

    @Test func purgeRemovesOldDataButNeverOpenIncidents() throws {
        let store = try makeStore()
        try store.append(minute(10))
        try store.append(minute(500))
        let old = try store.beginIncident(at: 20, reasons: .cpu, bootTime: 0)
        try store.append([record(time: 30)], incident: old)
        try store.endIncident(old, at: 50)
        let open = try store.beginIncident(at: 40, reasons: .thermal, bootTime: 0)
        try store.append([record(time: 45), record(time: 600)], incident: open)

        try store.purge(olderThan: 100)

        #expect(try store.minutes(since: 0).map(\.start) == [500])
        #expect(try store.incidents(since: 0).map(\.id) == [open])
        #expect(try store.processes(inIncident: old).isEmpty)
        // Old samples of the open incident are purged; recent ones stay.
        #expect(try store.processes(inIncident: open).map(\.time) == [600])
    }

    @Test func incidentIDsAreNeverReused() throws {
        let store = try makeStore()
        let first = try store.beginIncident(at: 1, reasons: .cpu, bootTime: 0)
        try store.endIncident(first, at: 2)
        try store.purge(olderThan: 100)
        let second = try store.beginIncident(at: 200, reasons: .cpu, bootTime: 0)
        #expect(second > first)
    }

    @Test func danglingIncidentsAreClosedAsInterrupted() throws {
        let store = try makeStore()
        let id = try store.beginIncident(at: 100, reasons: .cpu, bootTime: 0)
        try store.append([record(time: 130)], incident: id)
        try store.closeDanglingIncidents()
        let incident = try #require(try store.incidents(since: 0).first)
        #expect(incident.ended == 130)
        #expect(incident.interrupted)
    }

    // MARK: Untrusted input

    /// Review finding (reproduced): a NULL name crashed the reader. Invalid rows are skipped.
    @Test func readerSkipsInvalidRows() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        FileManager.default.createFile(atPath: dbURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        chmod(dir.path, 0o700)
        // A tampered file with the right version but a looser schema.
        try raw(
            """
            CREATE TABLE incidents (id INTEGER PRIMARY KEY, started REAL, ended REAL, reasons INTEGER,
                boot_time REAL, interrupted INTEGER);
            CREATE TABLE incident_processes (incident_id INTEGER, time REAL, pid INTEGER, start_time INTEGER,
                uid INTEGER, name TEXT, cpu_seconds REAL, disk_written INTEGER, footprint INTEGER);
            CREATE TABLE system_minutes (start REAL, avg_busy_cores REAL, peak_busy_cores REAL, swapped INTEGER,
                peak_pressure INTEGER, peak_thermal INTEGER);
            INSERT INTO incidents VALUES (1, 0, 1, 1, 0, 0);
            INSERT INTO incident_processes VALUES (1, 0, 42, 1, 501, NULL, 1, 0, 0);
            INSERT INTO incident_processes VALUES (1, 0, -1, 1, 501, 'all', 1, 0, 0);
            INSERT INTO incident_processes VALUES (1, 0, 0, 1, 501, 'group', 1, 0, 0);
            INSERT INTO incident_processes VALUES (1, 0, 7, 1, 501, 'ok', -5, -9, -1);
            PRAGMA user_version = 1;
            """)
        let reader = try HistoryStore(url: dbURL, readOnly: true)
        let rows = try reader.processes(inIncident: 1)
        #expect(rows.map(\.delta.name) == ["ok"])
        #expect(rows.first?.delta.cpuSeconds == 0)
        #expect(rows.first?.delta.diskBytesWritten == 0)
    }
}
