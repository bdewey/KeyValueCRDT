import Foundation

/// Information about the number of entries in the database.
public struct Statistics: Equatable {
  public init(entryCount: Int, authorCount: Int, tombstoneCount: Int, authorTableIsConsistent: Bool) {
    self.entryCount = entryCount
    self.authorCount = authorCount
    self.tombstoneCount = tombstoneCount
    self.authorTableIsConsistent = authorTableIsConsistent
  }

  /// How many entries are in the database.
  public let entryCount: Int

  /// How many authors are in the database.
  public let authorCount: Int

  /// How many tombstones are in the database.
  public let tombstoneCount: Int

  /// `true` if the author table is consistent with entries. If this value is `false`, you should erase version history in this database.
  public let authorTableIsConsistent: Bool
}
