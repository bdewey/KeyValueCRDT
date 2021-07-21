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

  /// The file holding the key/value CRDT. If nil, this is an in-memory instsance.
  public let fileURL: URL?

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
    return records
      .map { Version($0) }
      .filter { $0.value != .null }
  }

  public func delete(
    key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.null, to: key, scope: scope, timestamp: timestamp)
  }

  public func merge(source: KeyValueCRDT) throws {
    try databaseWriter.write { localDB in
      var localVersion = VersionVector(try AuthorRecord.fetchAll(localDB))

      let (remoteVersion, remoteRecords) = try source.databaseWriter.read { remoteDB -> (VersionVector<AuthorVersionIdentifier, Int>, [EntryRecord]) in
        let remoteVersion = VersionVector(try AuthorRecord.fetchAll(remoteDB))
        let needs = localVersion.needList(toMatch: remoteVersion)
        let records = try EntryRecord.all().filter(needs).fetchAll(remoteDB)
        return (remoteVersion, records)
      }
      localVersion.formUnion(remoteVersion)
      try updateAuthors(localVersion, in: localDB)
      for record in remoteRecords {
        try record.insert(localDB)
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

  func updateAuthors(_ versionVector: VersionVector<AuthorVersionIdentifier, Int>, in db: Database) throws {
    for (key, value) in versionVector {
      let authorRecord = AuthorRecord(id: key.id, name: key.name, usn: value)
      try authorRecord.save(db)
    }
  }
}

private extension QueryInterfaceRequest where RowDecoder == EntryRecord {
  func filter(_ needsList: [(key: AuthorVersionIdentifier, value: Int?)]) -> QueryInterfaceRequest<EntryRecord> {
    self
  }
}
