// 

import Foundation
import KeyValueCRDT

internal struct GenericUpgrader: ApplicationDataUpgrader {
  let expectedApplicationIdentifier: ApplicationIdentifier
  let upgradeBlock: (() -> Void)?

  init(_ applicationIdentifier: ApplicationIdentifier, upgradeBlock: (() -> Void)? = nil) {
    self.expectedApplicationIdentifier = applicationIdentifier
    self.upgradeBlock = upgradeBlock
  }

  func upgradeApplicationData(in database: KeyValueDatabase) throws {
    upgradeBlock?()
  }
}
