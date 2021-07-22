import Foundation
import GRDB

/// Implements a key/value store CRDT backed by a single sqlite database.
public final class KeyValueCRDT {
  /// Initializes a CRDT using a specific file.
  /// - Parameters:
  ///   - fileURL: The file holding the key/value CRDT.
  ///   - author: The author for any changes to the CRDT created by this instance.
  public init(fileURL: URL?, author: Author) throws {
    self.author = author
    let databaseWriter: DatabaseWriter
    if let fileURL = fileURL {
      databaseWriter = try DatabasePool.openSharedDatabase(at: fileURL, migrator: .keyValueCRDT)
    } else {
      let queue = try DatabaseQueue(path: ":memory:")
      try DatabaseMigrator.keyValueCRDT.migrate(queue)
      databaseWriter = queue
    }
    let authorRecord = try databaseWriter.read { db in
      try AuthorRecord.filter(key: author.id).fetchOne(db)
    }
    self.databaseWriter = databaseWriter
    self.authorRecord = authorRecord ?? AuthorRecord(id: author.id, name: author.name, usn: 0)
  }

  // TODO: There's too much repetition between the initializers.
  /// Creates a CRDT from an existing, initialized `DatabaseWriter`
  public init(databaseWriter: DatabaseWriter, author: Author) throws {
    self.author = author
    self.databaseWriter = databaseWriter
    let authorRecord = try databaseWriter.read { db in
      try AuthorRecord.filter(key: author.id).fetchOne(db)
    }
    self.authorRecord = authorRecord ?? AuthorRecord(id: author.id, name: author.name, usn: 0)
  }

  /// Creates an in-memory clone of the database contents.
  public func makeMemoryDatabaseQueue() throws -> DatabaseQueue {
    let memoryQueue = try DatabaseQueue(path: ":memory:")
    try databaseWriter.backup(to: memoryQueue)
    return memoryQueue
  }

  /// The author for any changes to the CRDT made by this instance.
  public let author: Author

  private let databaseWriter: DatabaseWriter

  /// Holds the current author record so we don't have to keep re-reading it.
  private var authorRecord: AuthorRecord

  public func writeText(
    _ text: String,
    to key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.text(text), to: key, scope: scope, timestamp: timestamp)
  }

  public func read(
    key: String,
    scope: String = ""
  ) throws -> [Version] {
    let records = try databaseWriter.read { db in
      try EntryRecord
        .filter(EntryRecord.Column.key == key)
        .filter(EntryRecord.Column.scope == scope)
        .fetchAll(db)
    }
    return records.map { Version($0) }
  }

  public func delete(
    key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.null, to: key, scope: scope, timestamp: timestamp)
  }

  struct RemoteInfo {
    let version: VersionVector<AuthorVersionIdentifier, Int>
    let entries: [EntryRecord]
    let tombstones: [TombstoneRecord]
  }

  public func merge(source: KeyValueCRDT) throws {
    try databaseWriter.write { localDB in
      var localVersion = VersionVector(try AuthorRecord.fetchAll(localDB))

      let remoteInfo = try source.databaseWriter.read { remoteDB -> RemoteInfo in
        let remoteVersion = VersionVector(try AuthorRecord.fetchAll(remoteDB))
        let needs = localVersion.needList(toMatch: remoteVersion)
        let entries = try EntryRecord.all().filter(needs).fetchAll(remoteDB)
        let tombstones = try TombstoneRecord.all().filter(needs).fetchAll(remoteDB)
        return RemoteInfo(version: remoteVersion, entries: entries, tombstones: tombstones)
      }
      localVersion.formUnion(remoteInfo.version)
      try updateAuthors(localVersion, in: localDB)
      try processTombstones(remoteInfo.tombstones, in: localDB)
      for record in remoteInfo.entries {
        try record.save(localDB)
      }
    }
  }

  private func processTombstones(_ tombstones: [TombstoneRecord], in db: Database) throws {
    for tombstone in tombstones {
      let entry = try EntryRecord
        .filter(key: [
          EntryRecord.Column.scope.name: tombstone.scope,
          EntryRecord.Column.key.name: tombstone.key,
          EntryRecord.Column.authorId.name: tombstone.authorId,
        ])
        .fetchOne(db)
      guard let entry = entry else { continue }
      if entry.usn <= tombstone.usn {
        try entry.delete(db)
        try tombstone.insert(db)
      }
    }
  }
}

// MARK: - Private

private extension KeyValueCRDT {
  func incrementAuthorUSN(in database: Database) throws -> Int {
    authorRecord.usn += 1
    try authorRecord.save(database)
    return authorRecord.usn
  }

  func writeValue(
    _ value: Value,
    to key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try databaseWriter.write { db in
      let usn = try incrementAuthorUSN(in: db)
      try createTombstones(key: key, scope: scope, usn: usn, db: db)
      var entryRecord = EntryRecord(
        scope: scope,
        key: key,
        authorId: self.author.id,
        usn: usn,
        modifiedTimestamp: timestamp
      )
      entryRecord.value = value
      try entryRecord.save(db)
    }
  }

  func createTombstones(key: String, scope: String, usn: Int, db: Database) throws {
    let existingRecords = try EntryRecord
      .filter(EntryRecord.Column.key == key)
      .filter(EntryRecord.Column.scope == scope)
      .filter(EntryRecord.Column.authorId != author.id)
      .fetchAll(db)
    let tombstones = existingRecords.map { TombstoneRecord($0, deletingAuthorId: author.id, deletingUsn: usn) }
    try tombstones.forEach {
      try $0.insert(db)
    }
    try existingRecords.forEach {
      try $0.delete(db)
    }
  }

  func updateAuthors(_ versionVector: VersionVector<AuthorVersionIdentifier, Int>, in db: Database) throws {
    for (key, value) in versionVector {
      let authorRecord = AuthorRecord(id: key.id, name: key.name, usn: value)
      try authorRecord.save(db)
      if authorRecord.id == author.id {
        self.authorRecord = authorRecord
      }
    }
  }
}

private extension QueryInterfaceRequest where RowDecoder == EntryRecord {
  // TODO: Fix the "needsList" terminology -- this is terrible
  /// Filters the receiver to include only records greater than the versions specified by `needsList`
  func filter(_ needsList: [(key: AuthorVersionIdentifier, value: Int?)]) -> QueryInterfaceRequest<EntryRecord> {
    let expressions = needsList.map { (key, value) -> SQLSpecificExpressible in
      if let value = value {
        return EntryRecord.Column.authorId == key.id && EntryRecord.Column.usn > value
      } else {
        return EntryRecord.Column.authorId == key.id
      }
    }
    return self.filter(expressions.joined(operator: .or))
  }
}

private extension QueryInterfaceRequest where RowDecoder == TombstoneRecord {
  func filter(_ needsList: [(key: AuthorVersionIdentifier, value: Int?)]) -> QueryInterfaceRequest<TombstoneRecord> {
    let expressions = needsList.map { (key, value) -> SQLSpecificExpressible in
      if let value = value {
        return TombstoneRecord.Column.deletingAuthorId == key.id && TombstoneRecord.Column.deletingUsn > value
      } else {
        return TombstoneRecord.Column.deletingAuthorId == key.id
      }
    }
    return self.filter(expressions.joined(operator: .or))
  }
}
