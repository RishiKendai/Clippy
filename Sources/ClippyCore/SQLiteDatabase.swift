import Foundation
import SQLite3

/// Value that can be bound to a statement parameter or read from a column.
public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A row returned by `SQLiteDatabase.query`, addressed by column index.
public struct SQLRow: Sendable {
    let values: [SQLValue]

    public func int(_ i: Int) -> Int64 {
        if case let .int(v) = values[i] { return v }
        if case let .double(v) = values[i] { return Int64(v) }
        return 0
    }
    public func double(_ i: Int) -> Double {
        if case let .double(v) = values[i] { return v }
        if case let .int(v) = values[i] { return Double(v) }
        return 0
    }
    public func text(_ i: Int) -> String? {
        if case let .text(v) = values[i] { return v }
        return nil
    }
    public func blob(_ i: Int) -> Data? {
        if case let .blob(v) = values[i] { return v }
        return nil
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the sqlite3 C API. Not thread-safe by itself:
/// callers (ClipRepository) serialize access with a lock.
public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// Opens (creating if needed) the database at `path`. Use ":memory:" for tests.
    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError(code: rc, message: msg)
        }
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
        }
    }

    deinit { sqlite3_close_v2(handle) }

    /// Runs one or more statements with no parameters and no results.
    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: msg)
        }
    }

    /// Runs a single statement with parameters. Returns rows (empty for writes).
    @discardableResult
    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        var stmt: OpaquePointer?
        var rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw lastError(rc) }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .null: rc = sqlite3_bind_null(stmt, idx)
            case let .int(v): rc = sqlite3_bind_int64(stmt, idx, v)
            case let .double(v): rc = sqlite3_bind_double(stmt, idx, v)
            case let .text(v): rc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let .blob(v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress ?? UnsafeRawPointer(bitPattern: 1), Int32(v.count), SQLITE_TRANSIENT)
                }
            }
            guard rc == SQLITE_OK else { throw lastError(rc) }
        }

        var rows: [SQLRow] = []
        while true {
            rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw lastError(rc) }
            let count = sqlite3_column_count(stmt)
            var values: [SQLValue] = []
            values.reserveCapacity(Int(count))
            for c in 0..<count {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: values.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: values.append(.double(sqlite3_column_double(stmt, c)))
                case SQLITE_TEXT: values.append(.text(String(cString: sqlite3_column_text(stmt, c))))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    if let p = sqlite3_column_blob(stmt, c), n > 0 {
                        values.append(.blob(Data(bytes: p, count: n)))
                    } else {
                        values.append(.blob(Data()))
                    }
                default: values.append(.null)
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    /// Rows changed by the last INSERT/UPDATE/DELETE.
    public var changes: Int { Int(sqlite3_changes(handle)) }

    /// Runs `body` inside a transaction, rolling back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var userVersion: Int {
        get { (try? query("PRAGMA user_version").first?.int(0)).map { Int($0) } ?? 0 }
    }

    public func setUserVersion(_ v: Int) throws {
        try execute("PRAGMA user_version = \(v)")
    }

    private func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }
}
