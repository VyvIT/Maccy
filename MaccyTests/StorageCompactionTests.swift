import Foundation
import SQLite3
import Testing
@testable import Maccy

final class StorageCompactionTests {
  let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  var url: URL { directory.appending(path: "Storage.sqlite") }
  // Stands in for the connection Core Data keeps open while Maccy runs.
  var database: OpaquePointer?

  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
    // Core Data creates its stores like this.
    execute("PRAGMA auto_vacuum = INCREMENTAL; PRAGMA journal_mode = WAL;")
    execute("CREATE TABLE contents (value BLOB)")
  }

  deinit {
    sqlite3_close(database)
    try? FileManager.default.removeItem(at: directory)
  }

  @Test("Compaction gives the space of deleted history back to the disk")
  func shrinksDeletedHistory() throws {
    execute("INSERT INTO contents VALUES ('kept')")
    for _ in 0..<20 {
      execute("INSERT INTO contents VALUES (randomblob(256 * 1024))")
    }
    execute("PRAGMA wal_checkpoint")
    execute("DELETE FROM contents WHERE value != 'kept'")
    #expect(Storage.diskSize(of: url) > 5_000_000)

    Storage.compact(at: url)

    #expect(Storage.diskSize(of: url) < 100_000)
    #expect(count() == 1)
  }

  @Test("Compaction leaves a database without deletions as it is")
  func keepsHistory() {
    execute("INSERT INTO contents VALUES (randomblob(1024 * 1024))")

    Storage.compact(at: url)

    #expect(Storage.diskSize(of: url) > 1_000_000)
    #expect(count() == 1)
  }

  @Test("Compaction ignores a missing database")
  func ignoresMissingDatabase() {
    let missing = directory.appending(path: "Missing.sqlite")

    Storage.compact(at: missing)

    #expect(!FileManager.default.fileExists(atPath: missing.path))
  }

  @Test("Disk size includes the write-ahead log")
  func countsWriteAheadLog() throws {
    execute("INSERT INTO contents VALUES (randomblob(512 * 1024))")
    let walSize = try #require(
      try URL(filePath: url.path + "-wal").resourceValues(forKeys: [.fileSizeKey]).fileSize
    )
    let databaseSize = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)

    #expect(walSize > 512 * 1024)
    #expect(Storage.diskSize(of: url) == Int64(databaseSize + walSize))
  }

  private func execute(_ sql: String) {
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
  }

  private func count() -> Int {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    sqlite3_prepare_v2(database, "SELECT count(*) FROM contents", -1, &statement, nil)
    sqlite3_step(statement)
    return Int(sqlite3_column_int(statement, 0))
  }
}
