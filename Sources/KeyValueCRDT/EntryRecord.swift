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
        self.blobMimeType = mimeType
        self.blob = blob
      case .null:
        break
      }
    }
  }
}
