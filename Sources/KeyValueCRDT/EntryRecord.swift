//
//  File.swift
//  File
//
//  Created by Brian Dewey on 7/19/21.
//

import Foundation
import GRDB

/// A record in the `entry` table.
internal struct EntryRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "entry"

  var scope: String
  var key: String
  var authorId: UUID
  var usn: Int
  var modifiedTimestamp: Date
  var text: String?
  var json: String?
  var blob: Data?

  enum Column {
    static let key = GRDB.Column(CodingKeys.key)
    static let scope = GRDB.Column(CodingKeys.scope)
  }

  var value: Value {
    if let text = text {
      return .text(text)
    } else if let json = json {
      return .json(json)
    } else if let blob = blob {
      return .blob(blob)
    } else {
      return .null
    }
  }
}
