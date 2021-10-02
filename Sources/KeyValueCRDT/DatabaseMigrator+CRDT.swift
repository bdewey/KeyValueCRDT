//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

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
        td.column("type", .integer).notNull()
        td.primaryKey(["scope", "key", "authorId"])
        td.column("text", .text)
        td.column("json", .text)
        td.column("blobMimeType", .text)
        td.column("blob", .blob)
      })
      try db.create(virtualTable: "entryFullText", using: FTS5()) { table in
        table.synchronize(withTable: "entry")
        table.column("text")
        table.tokenizer = .porter(wrapping: .unicode61())
      }
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
    migrator.registerMigration("noTombstonePrimarykey") { db in
      try db.create(table: "tombstone_v2", body: { td in
        td.column("scope", .text).notNull()
        td.column("key", .text).notNull()
        td.column("authorId", .text).notNull().references("author", onDelete: .restrict)
        td.column("usn", .integer).notNull()
        td.column("deletingAuthorId", .text).notNull().references("author", onDelete: .restrict)
        td.column("deletingUsn", .integer).notNull()
      })
      try db.execute(sql: "INSERT INTO tombstone_v2 SELECT * FROM tombstone")
      try db.drop(table: "tombstone")
      try db.rename(table: "tombstone_v2", to: "tombstone")
      try db.create(index: "tombstone_deletingAuthor", on: "tombstone", columns: ["deletingAuthorId", "deletingUsn"])
    }
    migrator.registerMigration("authorTimestamp") { db in
      try db.alter(table: "author", body: { td in
        td.add(column: "timestamp", .datetime)
      })
    }
    migrator.registerMigration("applicationIdentifier") { db in
      try db.create(table: ApplicationIdentifier.databaseTableName, body: { td in
        td.column("id", .text).primaryKey()
        td.column("majorVersion", .integer).notNull()
        td.column("minorVersion", .integer).notNull()
        td.column("applicationDescription", .text)
      })
    }
    return migrator
  }()
}
