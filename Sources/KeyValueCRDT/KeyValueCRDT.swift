import Foundation
import GRDB

/// Implements a key/value CRDT backed by a single sqlite database.
///
/// `KeyValueCRDT` provides a *scoped* key/value storage backed by a single sqlite database. The database is a *conflict-free replicated data type* (CRDT), meaning
/// that multiple *authors* can edit copies of the database and later *merge* their changes and get consistent results. This makes `KeyValueCRDT` a good file format
/// for files in cloud storage, such as iCloud Documents. Different devices can make changes while offline and reliably merge their changes with the cloud version of the document.
///
/// `KeyValueCRDT` provides *multi-value register* semantics for the key/value pairs stored in the database. This means:
///
/// * An author can *write* a single value for a key.
/// * However, when *reading* a key, you may get multiple values. This happens when multiple authors make conflicting changes to a key -- the database keeps all of the conflicting
/// updates. Any author can resolve the conflict using an appropriate algorithm and writing the resolved value back to the database. `KeyValueCRDT` does not resolve any
/// conflicts on its own.
///
/// `KeyValueCRDT` provides *scoped* key/value storage. A *scope* is an arbitrary string that serves as a container for key/value pairs. The empty string is a valid scope
/// and is the default scope for key/value pairs.
public final class KeyValueCRDT {
  /// Initializes a CRDT using a specific file.
  /// - Parameters:
  ///   - fileURL: The file holding the key/value CRDT.
  ///   - author: The author for any changes to the CRDT created by this instance.
  public convenience init(fileURL: URL?, author: Author) throws {
    let databaseWriter: DatabaseWriter
    if let fileURL = fileURL {
      databaseWriter = try DatabasePool.openSharedDatabase(at: fileURL)
    } else {
      let queue = try DatabaseQueue(path: ":memory:")
      databaseWriter = queue
    }
    try self.init(databaseWriter: databaseWriter, author: author)
  }

  // TODO: There's too much repetition between the initializers.
  /// Creates a CRDT from an existing, initialized `DatabaseWriter`
  public init(databaseWriter: DatabaseWriter, author: Author) throws {
    try DatabaseMigrator.keyValueCRDT.migrate(databaseWriter)
    if try databaseWriter.read(DatabaseMigrator.keyValueCRDT.hasBeenSuperseded) {
      // Database is too recent
      throw KeyValueCRDTError.databaseSchemaTooNew
    }
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

  /// Gets the current number of entries in the database.
  public var statistics: Statistics {
    get throws {
      try databaseWriter.read { db in
        return Statistics(
          entryCount: try EntryRecord.fetchCount(db),
          authorCount: try AuthorRecord.fetchCount(db),
          tombstoneCount: try TombstoneRecord.fetchCount(db)
        )
      }
    }
  }

  /// All keys currently used in the database.
  public var keys: [ScopedKey] {
    get throws {
      try self.keys()
    }
  }

  /// All keys currently used in the database, optionally filtered by scope key.
  /// - Parameters:
  ///   - scope: If present, only keys in the matching scope will be returned.
  ///   - key: If present, only keys matching this key will be returned. This is useful to find all *scopes* that contain a key.
  /// - Returns: An array of *scope* / *key* pairs that match the given criteria.
  public func keys(scope: String? = nil, key: String? = nil) throws -> [ScopedKey] {
    var request = EntryRecord
      .filter(EntryRecord.Column.type != EntryRecord.EntryType.null.rawValue)
    if let scope = scope {
      request = request.filter(EntryRecord.Column.scope == scope)
    }
    if let key = key {
      request = request.filter(EntryRecord.Column.key == key)
    }
    return try databaseWriter.read { db in
      let rows = try Row.fetchAll(db, request)
      return rows.map { ScopedKey(scope: $0[0], key: $0[1]) }
    }
  }

  /// Writes text to the database.
  ///
  /// All text is full-text indexed. In addition to getting the text via ``read(key:scope:)``, you can also search for text with ``searchText(for:)``.
  ///
  /// - Parameters:
  ///   - text: The text to write.
  ///   - key: The key associated with the value.
  ///   - scope: The scope for the key.
  ///   - timestamp: The timestamp to associate with this update.
  public func writeText(
    _ text: String,
    to key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.text(text), to: key, scope: scope, timestamp: timestamp)
  }

  /// Writes json to the database.
  /// - Parameters:
  ///   - json: The json string to write.
  ///   - key: The key associated with the value.
  ///   - scope: The scope for the key.
  ///   - timestamp: The timestamp to associate with this update.
  /// - throws: KeyValueCRDTError.invalidJson if `json` is not a valid JSON string.
  public func writeJson(_ json: String, to key: String, scope: String = "", timestamp: Date = Date()) throws {
    try writeValue(.json(json), to: key, scope: scope, timestamp: timestamp)
  }

  /// Writes a data blob to the database.
  /// - Parameters:
  ///   - blob: The data to write.
  ///   - key: The key associated with the value.
  ///   - scope: The scope for the key.
  ///   - timestamp: The timestamp to associate with this update.
  public func writeBlob(
    _ blob: Data,
    to key: String,
    scope: String = "",
    mimeType: String = "application/octet-stream",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.blob(mimeType: mimeType, blob: blob), to: key, scope: scope, timestamp: timestamp)
  }

  /// Read the value associated with a key in the database.
  ///
  /// ``KeyValueCRDT`` provides *multi-value register* semantics. When writing to the database, you always write a *single* value for a key.
  /// However, when reading, you may get back *multiple values* in the event of an update conflict. It is up to the caller to decide what to do with multiple
  /// values. (Use the one with the latest timestamp? Have the user pick which one to keep? Just treat all values equally?)
  ///
  /// In the event that there is more than one value for a key, the caller can *resolve* the conflict using an arbitrary algorithm and writing the resolved value back
  /// to the database.
  ///
  /// - returns: An array of ``Version`` structs containing the values associated with the key. If the key has never been written to, this array will be empty. If there was
  /// an update conflict for the key, the array will contain more than one entry.
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

  /// Bulk-read: Returns the values for all matching keys.
  /// - Parameters:
  ///   - scope: If present, limits the results only to values in this scope.
  ///   - key: If present, limits the results only to values with this key.
  /// - Returns: A mapping of ``ScopedKey`` structs to ``Version`` arrays holding the values associated with the key. If there was an update conflict for the key, the ``Version`` array will contain more than one entry.
  public func bulkRead(scope: String? = nil, key: String? = nil) throws -> [ScopedKey: [Version]] {
    var query = EntryRecord.all()
    if let scope = scope {
      query = query.filter(EntryRecord.Column.scope == scope)
    }
    if let key = key {
      query = query.filter(EntryRecord.Column.key == key)
    }
    let records = try databaseWriter.read { db in
      try query.fetchAll(db)
    }
    return Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
  }

  /// Writes multiple values to the database in a single transaction.
  /// - Parameter values: Mapping of keys/values to write to the database.
  /// - Parameter timestamp: The timestamp to associate with the updated values.
  public func bulkWrite(_ values: [ScopedKey: Value], timestamp: Date = Date()) throws {
    try databaseWriter.write { db in
      let usn = try incrementAuthorUSN(in: db)
      for (key, value) in values {
        try writeValue(value, to: key.key, scope: key.scope, timestamp: timestamp, in: db, usn: usn)
      }
    }
  }

  /// Delete a key from the database.
  public func delete(
    key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws {
    try writeValue(.null, to: key, scope: scope, timestamp: timestamp)
  }

  /// Searches all text values for `searchTerm` and returns the matching keys.
  public func searchText(for searchTerm: String) throws -> [ScopedKey] {
    let pattern = FTS3Pattern(matchingAllTokensIn: searchTerm)
    let sql = """
SELECT entry.scope, entry.key
FROM entry
JOIN entryFullText ON entryFullText.rowId = entry.rowId AND entryFullText MATCH ?
"""
    return try databaseWriter.read { db in
      let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern])
      return rows.map { ScopedKey(scope: $0[0], key: $0[1]) }
    }
  }

  /// Merge another ``KeyValueCRDT`` into the receiver.
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
        try garbageCollectTombstones(for: record, in: localDB)
      }
    }
  }
}

// MARK: - Private

private extension KeyValueCRDT {
  struct RemoteInfo {
    let version: VersionVector<AuthorVersionIdentifier, Int>
    let entries: [EntryRecord]
    let tombstones: [TombstoneRecord]
  }

  func incrementAuthorUSN(in database: Database) throws -> Int {
    authorRecord.usn += 1
    try authorRecord.save(database)
    return authorRecord.usn
  }

  func writeValue(
    _ value: Value,
    to key: String,
    scope: String,
    timestamp: Date
  ) throws {
    try databaseWriter.write { db in
      let usn = try incrementAuthorUSN(in: db)
      try writeValue(value, to: key, scope: scope, timestamp: timestamp, in: db, usn: usn)
    }
  }

  func writeValue(
    _ value: Value,
    to key: String,
    scope: String,
    timestamp: Date,
    in db: Database,
    usn: Int
  ) throws {
    if let json = value.json {
      let result = try Int.fetchOne(db, sql: "SELECT json_valid(?);", arguments: [json])
      if result != 1 {
        throw KeyValueCRDTError.invalidJSON
      }
    }
    try createTombstones(key: key, scope: scope, usn: usn, db: db)
    var entryRecord = EntryRecord(
      scope: scope,
      key: key,
      authorId: self.author.id,
      usn: usn,
      timestamp: timestamp,
      type: value.entryType
    )
    entryRecord.value = value
    try entryRecord.save(db)
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

  func processTombstones(_ tombstones: [TombstoneRecord], in db: Database) throws {
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

  /// Remove any tombstones that are now obsolete because we have a new entry
  func garbageCollectTombstones(for entryRecord: EntryRecord, in db: Database) throws {
    try TombstoneRecord
      .filter(TombstoneRecord.Column.key == entryRecord.key)
      .filter(TombstoneRecord.Column.scope == entryRecord.scope)
      .filter(TombstoneRecord.Column.authorId == entryRecord.authorId)
      .filter(TombstoneRecord.Column.usn < entryRecord.usn)
      .deleteAll(db)
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
