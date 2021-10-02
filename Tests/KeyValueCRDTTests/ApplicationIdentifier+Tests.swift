// 

import Foundation
import KeyValueCRDT

internal extension ApplicationIdentifier {
  static let tests = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 1, minorVersion: 0)
  static let testsV2 = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 2, minorVersion: 0)
  static let testsV21 = ApplicationIdentifier(id: "org.brians-brain.KeyValueCRDTTests", majorVersion: 2, minorVersion: 1)
  static let differentApplication = ApplicationIdentifier(id: "org.brians-brain.dreaming", majorVersion: 13, minorVersion: 0)
}
