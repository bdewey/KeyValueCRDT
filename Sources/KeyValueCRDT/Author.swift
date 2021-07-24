import Foundation

/// Identifies the authors of changes to the database.
public struct Author: CustomStringConvertible {
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }

  public let id: UUID
  public var name: String

  public var description: String {
    "\(id) (\(name))"
  }
}
