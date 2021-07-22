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
        td.column("timestamp", .datetime).notNull()
        td.primaryKey(["scope", "key", "authorId"])
        td.column("text", .text)
        td.column("json", .text)
        td.column("blob", .blob)
      })
      try db.create(table: "tombstone", body: { td in
        td.column("scope", .text).notNull()
        td.column("key", .text).notNull()
        td.column("authorId", .text).notNull().references("author", onDelete: .restrict)
        td.column("usn", .integer).notNull()
        td.column("deletingAuthorId", .text).notNull().references("author", onDelete: .restrict)
        td.column("deletingUsn", .integer).notNull()
        td.primaryKey(["scope", "key", "deletingAuthorId", "deletingUsn"])
      })
    }
    return migrator
  }()
}
