import Foundation

public enum KeyValueCRDTError: Error {
  /// The CRDT database has a new version schema that this version does not understand.
  case databaseSchemaTooNew

  /// There are conflicting versions of a value in a code path that asserted there should be only one.
  case versionConflict
}