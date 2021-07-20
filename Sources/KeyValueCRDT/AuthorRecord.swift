//
//  File.swift
//  File
//
//  Created by Brian Dewey on 7/19/21.
//

import Foundation
import GRDB

/// Database representation of an entry in the Author table.
internal struct AuthorRecord: Codable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "author"
  var id: UUID
  var name: String
  var usn: Int

  enum Columns {
    static let id = Column(AuthorRecord.CodingKeys.id)
  }
}

