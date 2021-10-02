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

import Foundation
import GRDB

/// A record in the `entry` table.
internal struct EntryRecord: Codable, FetchableRecord, PersistableRecord {
  enum EntryType: Int, Codable {
    case null
    case text
    case json
    case blob
  }

  static let databaseTableName = "entry"

  var scope: String
  var key: String
  var authorId: UUID
  var usn: Int
  var timestamp: Date
  var type: EntryType
  var text: String?
  var json: String?
  var blobMimeType: String?
  var blob: Data?

  enum Column {
    static let key = GRDB.Column(CodingKeys.key)
    static let scope = GRDB.Column(CodingKeys.scope)
    static let authorId = GRDB.Column(CodingKeys.authorId)
    static let usn = GRDB.Column(CodingKeys.usn)
    static let type = GRDB.Column(CodingKeys.type)
    static let text = GRDB.Column(CodingKeys.text)
    static let json = GRDB.Column(CodingKeys.json)
    static let blob = GRDB.Column(CodingKeys.blob)
  }

  var value: Value {
    get {
      if let text = text {
        return .text(text)
      } else if let json = json {
        return .json(json)
      } else if let blob = blob {
        return .blob(mimeType: blobMimeType ?? "application/octet-stream", blob: blob)
      } else {
        return .null
      }
    }
    set {
      text = nil
      json = nil
      blobMimeType = nil
      blob = nil
      switch newValue {
      case .text(let text):
        self.text = text
      case .json(let json):
        self.json = json
      case .blob(let mimeType, let blob):
        blobMimeType = mimeType
        self.blob = blob
      case .null:
        break
      }
    }
  }
}
