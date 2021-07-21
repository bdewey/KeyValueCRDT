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
    static let authorId = GRDB.Column(CodingKeys.authorId)
    static let usn = GRDB.Column(CodingKeys.usn)
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
        return .blob(blob)
      } else {
        fatalError("Entry has no corresponding value")
      }
    }
    set {
      text = nil
      json = nil
      blob = nil
      switch newValue {
      case .text(let text):
        self.text = text
      case .json(let json):
        self.json = json
      case .blob(let blob):
        self.blob = blob
      }
    }
  }
}
