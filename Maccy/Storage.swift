import AppKit.NSPasteboard
import Foundation
import SQLite3
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    let size = Self.diskSize(of: url)
    guard size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  private var isStoredOnDisk = true
  private var compactionTask: Task<Void, Never>?

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if AppDelegate.isTesting {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
      isStoredOnDisk = false
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  // Compacts the database shortly after the last of a batch of deletions.
  func scheduleCompaction(after delay: Duration = .seconds(5)) {
    guard isStoredOnDisk else {
      return
    }

    compactionTask?.cancel()
    compactionTask = Task { [url] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else {
        return
      }

      await Task.detached(priority: .utility) {
        Self.compact(at: url)
      }.value
    }
  }

  // Deleted history items leave free pages behind. Core Data uses incremental
  // auto-vacuum, so they are only released by an explicit vacuum, and the file
  // only shrinks once the write-ahead log is fully checkpointed, which never
  // happens while the store stays open. Without this, the database keeps the
  // size of the largest history it ever had, e.g. after copying images.
  nonisolated static func compact(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }

    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      return
    }

    // Wait for Core Data to finish writing instead of failing right away.
    sqlite3_busy_timeout(database, 2000)
    sqlite3_exec(database, "PRAGMA incremental_vacuum; PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
  }

  // Recent changes are kept in the write-ahead log next to the database.
  nonisolated static func diskSize(of url: URL) -> Int64 {
    [url, URL(filePath: url.path + "-wal")].reduce(0) { total, file in
      let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
      return total + Int64(size ?? 0)
    }
  }

  func cleanupOrphanedContents() throws -> Int {
    let descriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )
    let count = try context.fetchCount(descriptor)
    guard count > 0 else {
      return 0
    }

    try context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
    context.processPendingChanges()
    try context.save()

    return count
  }

  func removeUnpersistableContents() throws -> Int {
    let contents = try context.fetch(FetchDescriptor<HistoryItemContent>())
    let unwanted = contents.filter {
      !Clipboard.shared.isPersistable(NSPasteboard.PasteboardType($0.type))
    }

    guard !unwanted.isEmpty else {
      return 0
    }

    unwanted.forEach(context.delete)
    context.processPendingChanges()
    try context.save()

    return unwanted.count
  }

  // Titles stored before the sanitization in `HistoryItem.generateTitle()` may
  // contain scalars that hang CoreText on macOS 26. Such an item makes Maccy
  // spin at 100% CPU on every launch without ever drawing its window, so the
  // store has to be healed before the history is first rendered.
  // See https://github.com/p0deje/Maccy/issues/1520.
  func sanitizeTitles() throws -> Int {
    let items = try context.fetch(FetchDescriptor<HistoryItem>())
    var count = 0

    for item in items where item.title.containsScalarsUnsafeForTitleLayout {
      item.title = item.title.removingScalarsUnsafeForTitleLayout()
      count += 1
    }

    guard count > 0 else {
      return 0
    }

    context.processPendingChanges()
    try context.save()

    return count
  }
}
