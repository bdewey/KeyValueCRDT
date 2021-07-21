import Foundation

/// The kinds of values that can be stored in the database.
public enum Value: Equatable {
  case null
  case text(String)
  case json(String)
  case blob(Data)

  public var text: String? {
    if case .text(let text) = self {
      return text
    } else {
      return nil
    }
  }
}
