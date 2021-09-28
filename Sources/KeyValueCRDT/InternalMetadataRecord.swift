// 

import Foundation
import GRDB

internal struct InternalMetadataRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
  static let databaseTableName = "kvcrdt_metadata"

  var id: Int
  var majorVersion: Int
  var minorVersion: Int
}
