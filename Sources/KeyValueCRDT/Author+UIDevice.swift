#if !os(macOS)

import Foundation
import UIKit

public extension Author {
  /// Create an Author from a `UIDevice`.
  init?(_ device: UIDevice) {
    guard let id = device.identifierForVendor else { return nil }
    self.init(id: id, name: device.name)
  }
}

#endif
