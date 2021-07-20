import Foundation

public enum KeyValueCRDTError: Error {
  /// The CRDT database has a new version schema that this version does not understand.
  case databaseSchemaTooNew
}
