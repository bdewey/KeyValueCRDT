import Foundation
import GRDB

/// Implements a key/value store CRDT backed by a single sqlite database.
public final class KeyValueCRDT {
  /// Initializes a CRDT using a specific file.
  /// - Parameters:
  ///   - fileURL: The file holding the key/value CRDT.
  ///   - author: The author for any changes to the CRDT created by this instance.
  public init(fileURL: URL?, author: Author) throws {
    self.fileURL = fileURL
    self.author = author
    if let fileURL = fileURL {
      self.databaseWriter = try DatabasePool.openSharedDatabase(at: fileURL, migrator: .keyValueCRDT)
    } else {
      let queue = try DatabaseQueue(path: ":memory:")
      try DatabaseMigrator.keyValueCRDT.migrate(queue)
      self.databaseWriter = queue
    }
  }

  /// The file holding the key/value CRDT.
  public let fileURL: URL?

  /// The author for any changes to the CRDT made by this instance.
  public let author: Author

  private let databaseWriter: DatabaseWriter

  /// The kinds of values that can be stored in the database.
  public enum Value: Equatable {
    case null
    case text(String)
    case json(String)
    case blob(Data)
  }

  public struct TimestampedValue: Equatable {
    public var timestamp: Date
    public var value: Value
  }

  /// Stores a value into the database.
  public func setValue(
    _ value: Value,
    key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try databaseWriter.write { db in
      var authorRecord = try AuthorRecord.filter(key: self.author.id).fetchOne(db)
      if authorRecord == nil {
        authorRecord = AuthorRecord(id: self.author.id, name: self.author.name, usn: 0)
      }
      authorRecord!.usn += 1
      try authorRecord!.save(db)
      let entryRecord = EntryRecord(
        scope: scope,
        key: key,
        authorId: self.author.id,
        usn: authorRecord!.usn,
        modifiedTimestamp: timestamp,
        text: nil,
        json: nil,
        blob: nil
      )
      try entryRecord.insert(db)
    }
  }

  public func writeText(
    _ text: String,
    to key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try databaseWriter.write { db in
      var authorRecord = try AuthorRecord.filter(key: self.author.id).fetchOne(db)
      if authorRecord == nil {
        authorRecord = AuthorRecord(id: self.author.id, name: self.author.name, usn: 0)
      }
      authorRecord!.usn += 1
      try authorRecord!.save(db)
      let entryRecord = EntryRecord(
        scope: scope,
        key: key,
        authorId: self.author.id,
        usn: authorRecord!.usn,
        modifiedTimestamp: timestamp,
        text: text,
        json: nil,
        blob: nil
      )
      try entryRecord.insert(db)
    }
  }

  public func read(
    key: String,
    scope: String = ""
  ) throws -> [UUID: TimestampedValue] {
    let records = try databaseWriter.read { db in
      try EntryRecord
        .filter(EntryRecord.Column.key == key)
        .filter(EntryRecord.Column.scope == scope)
        .fetchAll(db)
    }
    let tuples = records.map { (key: $0.authorId, value: $0.timestampedValue) }
    return Dictionary<UUID, TimestampedValue>(tuples, uniquingKeysWith: { a, b in
      a.timestamp > b.timestamp ? a : b
    })
  }
}
