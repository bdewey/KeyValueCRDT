import Foundation
import GRDB

internal struct TombstoneRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "tombstone"
  var scope: String
  var key: String
  var authorId: UUID
  var usn: Int
  var deletingAuthorId: UUID
  var deletingUsn: Int

  enum Column {
    static let scope = GRDB.Column(CodingKeys.scope)
    static let key = GRDB.Column(CodingKeys.key)
    static let authorId = GRDB.Column(CodingKeys.authorId)
    static let usn = GRDB.Column(CodingKeys.usn)
    static let deletingAuthorId = GRDB.Column(CodingKeys.deletingAuthorId)
    static let deletingUsn = GRDB.Column(CodingKeys.deletingUsn)
  }
}

extension TombstoneRecord {
  init(_ entryRecord: EntryRecord, deletingAuthorId: UUID, deletingUsn: Int) {
    self.scope = entryRecord.scope
    self.key = entryRecord.key
    self.authorId = entryRecord.authorId
    self.usn = entryRecord.usn
    self.deletingAuthorId = deletingAuthorId
    self.deletingUsn = deletingUsn
  }
}
