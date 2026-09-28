import Darwin
import Foundation
import SQLite3

enum HelperDatabaseError: Error { case unsafePath, sqlite }

final class HelperDatabase: @unchecked Sendable {
    let pointer: OpaquePointer

    init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o022 == 0 else { throw HelperDatabaseError.unsafePath }
        guard let resolvedDirectory = realpath(directory.path, nil) else {
            throw HelperDatabaseError.unsafePath
        }
        defer { free(resolvedDirectory) }
        let resolvedURL = URL(fileURLWithPath: String(cString: resolvedDirectory))
            .appendingPathComponent(url.lastPathComponent)
        var fileInfo = stat()
        if lstat(resolvedURL.path, &fileInfo) == 0 {
            guard (fileInfo.st_mode & S_IFMT) == S_IFREG,
                  fileInfo.st_uid == getuid() else { throw HelperDatabaseError.unsafePath }
        }
        var opened: OpaquePointer?
        guard sqlite3_open_v2(
            resolvedURL.path, &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil
        ) == SQLITE_OK, let opened else {
            if let opened { sqlite3_close(opened) }
            throw HelperDatabaseError.sqlite
        }
        pointer = opened
        guard chmod(resolvedURL.path, 0o600) == 0 else { throw HelperDatabaseError.unsafePath }
        sqlite3_busy_timeout(opened, 2_000)
        try execute("PRAGMA journal_mode=DELETE")
        try execute("PRAGMA synchronous=FULL")
    }

    deinit { sqlite3_close(pointer) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else {
            throw HelperDatabaseError.sqlite
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw HelperDatabaseError.sqlite }
        return statement
    }
}

let helperSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func bindText(_ text: String, to statement: OpaquePointer, at index: Int32) {
    sqlite3_bind_text(statement, index, text, -1, helperSQLiteTransient)
}

func bindData(_ data: Data, to statement: OpaquePointer, at index: Int32) {
    _ = data.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), helperSQLiteTransient)
    }
}

func readData(_ statement: OpaquePointer, at index: Int32, maximumBytes: Int = 65_536) -> Data? {
    let count = Int(sqlite3_column_bytes(statement, index))
    guard (1...maximumBytes).contains(count), let pointer = sqlite3_column_blob(statement, index) else { return nil }
    return Data(bytes: pointer, count: count)
}
