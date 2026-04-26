import Foundation
import SQLite3

public enum SQLiteStoreError: Error, CustomStringConvertible, Equatable {
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case bindFailed(index: Int32, message: String)
    case stepFailed(sql: String, message: String)
    case missingColumn(name: String)
    case invalidTextColumn(index: Int32)

    public var description: String {
        switch self {
        case let .openFailed(path, message):
            "Could not open SQLite database at \(path): \(message)"
        case let .prepareFailed(sql, message):
            "Could not prepare SQLite statement \(sql): \(message)"
        case let .bindFailed(index, message):
            "Could not bind SQLite value at index \(index): \(message)"
        case let .stepFailed(sql, message):
            "Could not step SQLite statement \(sql): \(message)"
        case let .missingColumn(name):
            "Missing SQLite column \(name)"
        case let .invalidTextColumn(index):
            "Invalid SQLite text column at index \(index)"
        }
    }
}

public enum SQLiteValue: Equatable {
    case null
    case text(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private let path: String

    public init(path: String) throws {
        self.path = path
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            throw SQLiteStoreError.openFailed(path: path, message: message)
        }
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.stepFailed(sql: sql, message: message)
        }
    }

    public func run(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            throw SQLiteStoreError.stepFailed(sql: sql, message: lastErrorMessage)
        }
    }

    public func query<T>(_ sql: String, bindings: [SQLiteValue] = [], row: (SQLiteRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try row(SQLiteRow(statement: statement)))
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw SQLiteStoreError.stepFailed(sql: sql, message: lastErrorMessage)
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteStoreError.prepareFailed(sql: sql, message: lastErrorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case let .text(text):
                result = sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            case let .int(int):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(int))
            case let .int64(int64):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(int64))
            case let .double(double):
                result = sqlite3_bind_double(statement, index, double)
            }
            if result != SQLITE_OK {
                throw SQLiteStoreError.bindFailed(index: index, message: lastErrorMessage)
            }
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }
}

public struct SQLiteRow {
    fileprivate let statement: OpaquePointer?

    public func text(_ index: Int32) throws -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            throw SQLiteStoreError.invalidTextColumn(index: index)
        }
        return String(cString: cString)
    }

    public func optionalText(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    public func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    public func optionalInt(_ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : int(index)
    }

    public func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
