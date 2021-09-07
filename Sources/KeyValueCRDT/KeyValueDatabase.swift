import Combine
import Foundation
import GRDB
import Logging

private extension Logger {
  static let kvcrdt: Logger = {
    var logger = Logger(label: "org.brians-brain.kvcrdt")
    logger.logLevel = .debug
    return logger
  }()
}

/// Implements a key/value CRDT backed by a single sqlite database.
///
/// `KeyValueDatabase` provides a *scoped* key/value storage backed by a single sqlite database. The database is a *conflict-free replicated data type* (CRDT), meaning
/// that multiple *authors* can edit copies of the database and later *merge* their changes and get consistent results. This makes `KeyValueDatabase` a good file format
/// for files in cloud storage, such as iCloud Documents. Different devices can make changes while offline and reliably merge their changes with the cloud version of the document.
///
/// `KeyValueDatabase` provides *multi-value register* semantics for the key/value pairs stored in the database. This means:
///
/// * An author can *write* a single value for a key.
/// * However, when *reading* a key, you may get multiple values. This happens when multiple authors make conflicting changes to a key -- the database keeps all of the conflicting
/// updates. Any author can resolve the conflict using an appropriate algorithm and writing the resolved value back to the database. `KeyValueDatabase` does not resolve any
/// conflicts on its own.
///
/// `KeyValueDatabase` provides *scoped* key/value storage. A *scope* is an arbitrary string that serves as a container for key/value pairs. The empty string is a valid scope
/// and is the default scope for key/value pairs.
public final class KeyValueDatabase {
  /// Initializes a CRDT using a specific file.
  /// - Parameters:
  ///   - fileURL: The file holding the key/value CRDT.
  ///   - author: The author for any changes to the CRDT created by this instance.
  public convenience init(fileURL: URL?, authorDescription: String) throws {
    let databaseWriter: DatabaseWriter
    if let fileURL = fileURL {
      databaseWriter = try DatabaseQueue.openSharedDatabase(at: fileURL)
    } else {
      let queue = try DatabaseQueue(path: ":memory:")
      databaseWriter = queue
    }
    try self.init(databaseWriter: databaseWriter, authorDescription: authorDescription)
  }

  /// Creates a CRDT from an existing, initialized `DatabaseWriter`
  public init(databaseWriter: DatabaseWriter, authorDescription: String) throws {
    try DatabaseMigrator.keyValueCRDT.migrate(databaseWriter)
    if try databaseWriter.read(DatabaseMigrator.keyValueCRDT.hasBeenSuperseded) {
      // Database is too recent
      throw KeyValueCRDTError.databaseSchemaTooNew
    }
    self.databaseWriter = databaseWriter
    self.instanceID = UUID()
    self.authorRecord = AuthorRecord(id: instanceID, name: authorDescription, usn: 0, timestamp: Date())
  }

  /// Creates an in-memory clone of the database contents.
  public func makeMemoryDatabaseQueue() throws -> DatabaseQueue {
    let memoryQueue = try DatabaseQueue(path: ":memory:")
    try databaseWriter.backup(to: memoryQueue)
    return memoryQueue
  }

  /// Identifies this single open instance of the database.
  public let instanceID: UUID

  /// Publishes individual updates to the database.
  ///
  /// In contrast with ``readPublisher(scope:key:)``, which republishes *all* values when *anything* changes, this publisher publishes only the changed values.
  public private(set) lazy var updatedValuesPublisher: AnyPublisher<(ScopedKey, [Version]), Never> = updatedValueSubject.eraseToAnyPublisher()

  /// For publishing individual changes to the database.
  private let updatedValueSubject = PassthroughSubject<(ScopedKey, [Version]), Never>()

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
          tombstoneCount: try TombstoneRecord.fetchCount(db),
          authorTableIsConsistent: authorTableIsConsistent(in: db)
        )
      }
    }
  }

  /// Read data from the database inside a transaction.
  public func read<T>(block: (Database) throws -> T) throws -> T {
    try databaseWriter.read { db in
      try block(db)
    }
  }

  /// Perform a sequence of operations that change the database inside a transaction.
  public func write(block: (Database) throws -> Void) throws {
    try databaseWriter.write { db in
      try block(db)
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
  @discardableResult
  public func writeText(
    _ text: String,
    to key: String,
    scope: String = "",
    timestamp: Date = Date()
  ) throws -> Int {
    try writeValue(.text(text), to: key, scope: scope, timestamp: timestamp)
  }

  /// Writes json to the database.
  /// - Parameters:
  ///   - json: The json string to write.
  ///   - key: The key associated with the value.
  ///   - scope: The scope for the key.
  ///   - timestamp: The timestamp to associate with this update.
  /// - throws: KeyValueCRDTError.invalidJson if `json` is not a valid JSON string.
  @discardableResult
  public func writeJson(_ json: String, to key: String, scope: String = "", timestamp: Date = Date()) throws -> Int {
    try writeValue(.json(json), to: key, scope: scope, timestamp: timestamp)
  }

  /// Writes a data blob to the database.
  /// - Parameters:
  ///   - blob: The data to write.
  ///   - key: The key associated with the value.
  ///   - scope: The scope for the key.
  ///   - timestamp: The timestamp to associate with this update.
  @discardableResult
  public func writeBlob(
    _ blob: Data,
    to key: String,
    scope: String = "",
    mimeType: String = "application/octet-stream",
    timestamp: Date = Date()
  ) throws -> Int {
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

  private func read(scopedKey: ScopedKey, db: Database) throws -> [Version] {
    let records = try EntryRecord
      .filter(EntryRecord.Column.key == scopedKey.key)
      .filter(EntryRecord.Column.scope == scopedKey.scope)
      .fetchAll(db)
    return records.map { Version($0) }
  }

  /// Bulk-read: Returns the values for all matching keys.
  /// - Parameters:
  ///   - scope: If present, limits the results only to values in this scope.
  ///   - key: If present, limits the results only to values with this key.
  /// - Returns: A mapping of ``ScopedKey`` structs to ``Version`` arrays holding the values associated with the key. If there was an update conflict for the key, the ``Version`` array will contain more than one entry.
  public func bulkRead(scope: String? = nil, key: String? = nil) throws -> [ScopedKey: [Version]] {
    try databaseWriter.read { db in
      try bulkRead(database: db, scope: scope, key: key)
    }
  }

  /// Returns the values for all matching keys.
  /// - Parameters:
  ///   - database: A database obtained either through ``read(block:)`` or ``write(block:)``
  ///   - scope: If present, limits the results only to values in this scope.
  ///   - key: If present, limits the results only to values with this key.
  /// - Returns: A mapping of ``ScopedKey`` structs to ``Version`` arrays holding the values associated with the key. If there was an update conflict for the key, the ``Version`` array will contain more than one entry.
  public func bulkRead(database: Database, scope: String? = nil, key: String? = nil) throws -> [ScopedKey: [Version]] {
    var query = EntryRecord.all()
    if let scope = scope {
      query = query.filter(EntryRecord.Column.scope == scope)
    }
    if let key = key {
      query = query.filter(EntryRecord.Column.key == key)
    }
    let records = try query.fetchAll(database)
    return Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
  }

  public func bulkReadAllScopes(keyPrefix: String) throws -> [ScopedKey: [Version]] {
    let records = try databaseWriter.read { db in
      try EntryRecord.filter(EntryRecord.Column.key.like("\(keyPrefix)%")).fetchAll(db)
    }
    return Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
  }

  public func bulkRead(keys: [String]) throws -> [ScopedKey: [Version]] {
    let records = try databaseWriter.read { db -> [EntryRecord] in
      let keyList = keys
        .map({ "'\($0)'" }) // Wrap each string in double quotes
        .joined(separator: ", ") // comma separate
      return try EntryRecord.filter(sql: "key IN (\(keyList))").fetchAll(db)
    }
    return Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
  }

  public func bulkRead(isIncluded: (String, String) -> Bool) throws -> [ScopedKey: [Version]] {
    try databaseWriter.read { db in
      try bulkRead(database: db, isIncluded: isIncluded)
    }
  }

  /// Read data from the database.
  /// - Parameters:
  ///   - database: A `Database` object obtained from ``read(block:)`` or ``write(block:)``
  ///   - isIncluded: A block that receives the key and scope associated with an entry and returns `true` if the entry should be in the result.
  /// - Returns: A dictionary mapping entry scopes/keys with their values.
  public func bulkRead(database: Database, isIncluded: (String, String) -> Bool) throws -> [ScopedKey: [Version]] {
    let recordCursor = try EntryRecord.fetchCursor(database)
    var records = [EntryRecord]()
    while let record = try recordCursor.next() {
      if isIncluded(record.scope, record.key) {
        records.append(record)
      }
    }
    return Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
  }

  /// Publishes changes to the values for any matching key.
  /// - Parameters:
  ///   - scope: If present, limits the results only to values in this scope.
  ///   - key: If present, limits the results only to values with this key.
  /// - Returns: A publisher of mappings of ``ScopedKey`` structs to ``Version`` arrays holding the values associated with the key.
  public func readPublisher(scope: String? = nil, key: String? = nil) -> AnyPublisher<[ScopedKey: [Version]], Error> {
    var query = EntryRecord.all()
    if let scope = scope {
      query = query.filter(EntryRecord.Column.scope == scope)
    }
    if let key = key {
      query = query.filter(EntryRecord.Column.key == key)
    }
    return publisher(for: query)
  }

  /// Publishes changes for any key starting with a given prefix.
  /// - Parameter keyPrefix: The prefix for matching keys.
  /// - Returns: A publisher of mappings of ``ScopedKey`` structs to ``Version`` arrays holding values associated with the key.
  public func readPublisher(keyPrefix: String) -> AnyPublisher<[ScopedKey: [Version]], Error> {
    let query = EntryRecord.filter(EntryRecord.Column.key.like("\(keyPrefix)%"))
    return publisher(for: query)
  }

  private func publisher(for query: QueryInterfaceRequest<EntryRecord>) -> AnyPublisher<[ScopedKey: [Version]], Error> {
    return ValueObservation
      .tracking(query.fetchAll)
      .map({ records in
        Dictionary(grouping: records, by: ScopedKey.init).mapValues({ $0.map(Version.init) })
      })
      .publisher(in: databaseWriter)
      .eraseToAnyPublisher()
  }

  /// Publishes a notification whenever there are changes to matching keys.
  /// - Parameters:
  ///   - scope: If present, limits the results only to values in this scope.
  ///   - key: If present, limits the results only to values with this key.
  /// - Returns: A publisher of mappings of ``ScopedKey`` structs to ``Version`` arrays holding the values associated with the key.
  public func didChangePublisher(scope: String? = nil, key: String? = nil) -> AnyPublisher<Database, Error> {
    var query = EntryRecord.all()
    if let scope = scope {
      query = query.filter(EntryRecord.Column.scope == scope)
    }
    if let key = key {
      query = query.filter(EntryRecord.Column.key == key)
    }
    return DatabaseRegionObservation(tracking: query)
      .publisher(in: databaseWriter)
      .eraseToAnyPublisher()
  }

  /// Writes multiple values to the database in a single transaction.
  /// - Parameter values: Mapping of keys/values to write to the database.
  /// - Parameter timestamp: The timestamp to associate with the updated values.
  @discardableResult
  public func bulkWrite(_ values: [ScopedKey: Value], timestamp: Date = Date()) throws -> Int {
    let usn = try databaseWriter.write { db -> Int in
      let usn = try incrementAuthorUSN(in: db)
      for (key, value) in values {
        _ = try writeValue(value, to: key.key, scope: key.scope, timestamp: timestamp, in: db, usn: usn)
      }
      assert(authorTableIsConsistent(in: db))
      return usn
    }
    values
      .map { ($0.key, [Version(authorID: instanceID, timestamp: timestamp, value: $0.value)]) }
      .forEach { updatedValueSubject.send($0) }
    return usn
  }

  /// Writes multiple values to the database in a single transaction.
  /// - Parameters:
  ///   - database: A database obtained by ``write(block:)``
  ///   - values: Mapping of keys/values to write to the database.
  ///   - timestamp: The timestamp to associate with the updated values.
  public func bulkWrite(database: Database, values: [ScopedKey: Value], timestamp: Date = Date()) throws {
    let usn = try incrementAuthorUSN(in: database)
    for (key, value) in values {
      _ = try writeValue(value, to: key.key, scope: key.scope, timestamp: timestamp, in: database, usn: usn)
    }
    values
      .map { ($0.key, [Version(authorID: instanceID, timestamp: timestamp, value: $0.value)]) }
      .forEach { updatedValueSubject.send($0) }
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
    let pattern = FTS5Pattern(matchingAllTokensIn: searchTerm)
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

  /// Returns true if the receiver "dominates" `other`.
  ///
  /// A CRDT **A** dominates a CRDT **B** if, for all keys in **B**, **A** has a version that is greater than or equal to that version.
  /// In other words, there is nothing in **B** that **A** does not already know about.
  ///
  /// One implication of this definition is a CRDT dominates itself... `crdt.dominates(other: crdt)` is always true.
  ///
  /// - parameter other: The CRDT to compare to.
  /// - returns: True if the receiver dominates `other`
  public func dominates(other: KeyValueDatabase) throws -> Bool {
    try databaseWriter.read { localDB in
      let localVersion = VersionVector(try AuthorRecord.fetchAll(localDB))
      let remoteVersion = try other.databaseWriter.read { remoteDB in
        VersionVector(try AuthorRecord.fetchAll(remoteDB))
      }
      return localVersion.dominates(remoteVersion)
    }
  }

  /// Merge another ``KeyValueDatabase`` into the receiver.
  ///
  /// - Parameters:
  ///   - source: The database to merge into the receiver.
  ///   - dryRun: If true, don't actually merge; just compute what will change.
  /// - returns: The keys that changed because of this merge.
  @discardableResult
  public func merge(source: KeyValueDatabase, dryRun: Bool = false) throws -> Set<ScopedKey> {
    var updatedKeys = Set<ScopedKey>()
    var updatedValues: [(ScopedKey, [Version])] = []
    try databaseWriter.write { localDB in
      assert(authorTableIsConsistent(in: localDB))
      var localVersion = VersionVector(try AuthorRecord.fetchAll(localDB))

      let remoteInfo = try source.databaseWriter.read { remoteDB -> RemoteInfo in
        assert(source.authorTableIsConsistent(in: remoteDB))
        let remoteVersion = VersionVector(try AuthorRecord.fetchAll(remoteDB))
        let needs = localVersion.needList(toMatch: remoteVersion)
        let entries = try EntryRecord.all().filter(needs).fetchAll(remoteDB)
        let tombstones = try TombstoneRecord.all().filter(needs).fetchAll(remoteDB)
        return RemoteInfo(version: remoteVersion, entries: entries, tombstones: tombstones)
      }
      if !dryRun {
        localVersion.formUnion(remoteInfo.version)
        try updateAuthors(localVersion, in: localDB)
        try processTombstones(remoteInfo.tombstones, in: localDB)
        for record in remoteInfo.entries {
          try record.save(localDB)
          try garbageCollectTombstones(for: record, in: localDB)
          updatedKeys.insert(ScopedKey(record))
        }
        assert(authorTableIsConsistent(in: localDB))
        updatedValues = try updatedKeys.map { ($0, try read(scopedKey: $0, db: localDB)) }
      }
    }
    for updatedValue in updatedValues {
      updatedValueSubject.send(updatedValue)
    }
    return updatedKeys
  }

  /// Backs up this CRDT to another CRDT.
  ///
  /// The expectation is `destination` is empty; any contents it has will be overwritten.
  ///
  /// - note: While this method overwrites the contents of `destination`, it **does not** trigger updates for any publishers created by ``readPublisher(scope:key:)``
  /// or ``readPublisher(keyPrefix:)``.
  public func backup(to destination: KeyValueDatabase) throws {
    try databaseWriter.backup(to: destination.databaseWriter)
  }

  /// Erases the version history in this database.
  ///
  /// This method:
  ///
  /// - Removes all tombstones
  /// - Makes all content look like it comes from this author
  public func eraseVersionHistory() throws {
    try databaseWriter.write { db in
      try TombstoneRecord.deleteAll(db)
      authorRecord.usn += 1
      try authorRecord.save(db)
      try EntryRecord.updateAll(db, EntryRecord.Column.authorId.set(to: authorRecord.id), EntryRecord.Column.usn.set(to: authorRecord.usn))
      try AuthorRecord
        .filter(AuthorRecord.Columns.id != authorRecord.id)
        .deleteAll(db)
    }
  }

  /// Writes the contents of the CRDT to a file.
  ///
  /// The intended use is to write the contents of an in-memory CRDT to disk.
  public func save(to url: URL) throws {
    try databaseWriter.writeWithoutTransaction { db in
      try db.execute(sql: "VACUUM INTO '\(url.path)'")
    }
  }
}

// MARK: - Private

private extension KeyValueDatabase {
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

  @discardableResult
  func writeValue(
    _ value: Value,
    to key: String,
    scope: String,
    timestamp: Date
  ) throws -> Int {
    let record = try databaseWriter.write { db -> EntryRecord in
      let usn = try incrementAuthorUSN(in: db)
      return try writeValue(value, to: key, scope: scope, timestamp: timestamp, in: db, usn: usn)
    }
    updatedValueSubject.send((ScopedKey(scope: scope, key: key), [Version(record)]))
    return record.usn
  }

  func writeValue(
    _ value: Value,
    to key: String,
    scope: String,
    timestamp: Date,
    in db: Database,
    usn: Int
  ) throws -> EntryRecord {
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
      authorId: self.instanceID,
      usn: usn,
      timestamp: timestamp,
      type: value.entryType
    )
    entryRecord.value = value
    try entryRecord.save(db)
    assert(authorTableIsConsistent(in: db))
    return entryRecord
  }

  func createTombstones(key: String, scope: String, usn: Int, db: Database) throws {
    let existingRecords = try EntryRecord
      .filter(EntryRecord.Column.key == key)
      .filter(EntryRecord.Column.scope == scope)
      .filter(EntryRecord.Column.authorId != instanceID)
      .fetchAll(db)
    let tombstones = existingRecords.map { TombstoneRecord($0, deletingAuthorId: instanceID, deletingUsn: usn) }
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
      if authorRecord.id == instanceID {
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

  func authorTableIsConsistent(in db: Database) -> Bool {
    do {
      let authors = try AuthorRecord.fetchAll(db)
      let request = EntryRecord
        .select(EntryRecord.Column.authorId, max(EntryRecord.Column.usn))
        .group(EntryRecord.Column.authorId)
      let rows = try Row.fetchAll(db, request).map { row in
        (key: row[0] as UUID, value: row[1] as Int)
      }
      var maxUsn: [UUID: Int] = [:]
      for row in rows {
        maxUsn[row.key] = row.value
      }
      let authorVersionVector = VersionVector(authors)
      let entryVersionVector = VersionVector(rows)
      if !authorVersionVector.dominates(entryVersionVector) {
        let needs = authorVersionVector.needList(toMatch: entryVersionVector)
        Logger.kvcrdt.error("Author table inconsistent with entries: \(needs)")
        return false
      }
      return true
    } catch {
      Logger.kvcrdt.error("Unexpected error checking author table consistency: \(error)")
      return false
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
