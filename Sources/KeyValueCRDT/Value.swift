import Foundation

/// The kinds of values that can be stored in the database.
public enum Value: Equatable {
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
