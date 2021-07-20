import Foundation

/// The kinds of values that can be stored in the database.
public enum Value: Equatable {
  case null
  case text(String)
  case json(String)
  case blob(Data)
}
