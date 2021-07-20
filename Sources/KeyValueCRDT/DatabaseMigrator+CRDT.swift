import GRDB

internal extension DatabaseMigrator {
  /// The CRDT DatabaseMigrator.
  static let keyValueCRDT: DatabaseMigrator = {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("initialSchema") { db in
      try db.create(table: "author") { td in
        td.column("id", .text).notNull().primaryKey()
        td.column("name", .text).notNull()
        td.column("usn", .integer).notNull()
      }
      try db.create(table: "entry", body: { td in
        td.column("scope", .text).notNull()
        td.column("key", .text).notNull()
        td.column("authorId", .text).notNull().references("author", onDelete: .restrict)
        td.column("usn", .integer).notNull()
        td.column("modifiedTimestamp", .datetime).notNull()
        td.primaryKey(["scope", "key", "authorId"])
        td.column("text", .text)
        td.column("json", .text)
        td.column("blob", .blob)
      })
    }
    return migrator
  }()
}
