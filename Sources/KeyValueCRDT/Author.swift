import Foundation
import UIKit

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

public extension Author {
  /// Create an Author from a `UIDevice`.
  init?(_ device: UIDevice) {
    guard let id = device.identifierForVendor else { return nil }
    self.init(id: id, name: device.name)
  }
}
